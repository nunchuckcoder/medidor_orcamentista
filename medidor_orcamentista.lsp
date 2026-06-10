;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 Osvaldo Cipriano (github.com/nunchuckcoder)

;;-----------------------------------------------------------------------------;;
;;                      Início do carregamento do módulo                       ;;
;;-----------------------------------------------------------------------------;;

(princ "\nIniciando carregamento de medidor_orcamentista.lsp...")

;; --={  Separador decimal usado nos números exportados para CSV  }=--
;; --={  "," para Excel PT-PT | "." para formato internacional    }=--

(setq *MEDORC-DECIMAL* ",")

;;-----------------------------------------------------------------------------;;
;;                            Função de log de erros                           ;;
;;-----------------------------------------------------------------------------;;

(defun LogError (msg / file timestamp)

  ;; --={  Gravar erro no log sem interromper o programa  }=--
  ;; --={  Cria/abre "medicoes_log.txt" na pasta do desenho e escreve  }=--
  ;; --={  timestamp + mensagem  }=--

  (vl-catch-all-apply
    (function
      (lambda ()
        (setq timestamp (rtos (getvar "CDATE") 2 6))
        (setq file (open (strcat (getvar "DWGPREFIX") "medicoes_log.txt") "a"))
        (if file
          (progn
            (write-line (strcat timestamp ": " msg) file)
            (close file)
          )
        )
        (prompt (strcat "\n[LOG] " msg))  ; mostra log na linha de comando
      )
    )
    '()
  )
  (princ)
)

;;-----------------------------------------------------------------------------;;
;;                             Funções utilitárias                             ;;
;;-----------------------------------------------------------------------------;;

;; --={  Garantir que a layer existe, criando-a se necessário.       }=--
;; --={  Usa entmake para não alterar a layer corrente do desenho.   }=--

(defun EnsureLayer (layername /)
  (if (not (tblsearch "LAYER" layername))
    (entmake
      (list
        '(0 . "LAYER")
        '(100 . "AcDbSymbolTableRecord")
        '(100 . "AcDbLayerTableRecord")
        (cons 2 layername)
        '(70 . 0)
      )
    )
  )
  layername
)

;; --={  Calcular o comprimento de uma curva com segurança.          }=--
;; --={  Devolve nil se o objeto não tiver comprimento mensurável.   }=--

(defun CalcLength (obj / res)
  (setq res
    (vl-catch-all-apply
      (function
        (lambda ()
          (vlax-curve-getdistatparam obj (vlax-curve-getendparam obj))
        )
      )
      '()
    )
  )
  (if (vl-catch-all-error-p res) nil res)
)

;; --={  Calcular a área de um objeto com segurança.                 }=--
;; --={  Devolve nil se o objeto não tiver área mensurável.          }=--

(defun CalcArea (obj / res)
  (setq res (vl-catch-all-apply 'vla-get-Area (list obj)))
  (if (vl-catch-all-error-p res) nil res)
)

;; --={  Escapar aspas e colocar o texto entre aspas para CSV.       }=--
;; --={  Percorre toda a string (substitui TODAS as aspas internas). }=--

(defun EscapeCSV (str / out i ch)
  (if (not str) (setq str ""))
  (setq out "" i 1)
  (repeat (strlen str)
    (setq ch (substr str i 1))
    (setq out (strcat out (if (= ch "\"") "\"\"" ch)))
    (setq i (1+ i))
  )
  (strcat "\"" out "\"")
)

;; --={  Formatar número para CSV com o separador decimal definido   }=--
;; --={  em *MEDORC-DECIMAL*.                                        }=--

(defun NumCSV (v)
  (if (= *MEDORC-DECIMAL* ",")
    (vl-string-subst "," "." (rtos v 2 2))
    (rtos v 2 2)
  )
)

;; --={  Processar seleção de objetos: calcula total, muda cor e layer.  }=--
;; --={   - ss      : seleção de objetos                                 }=--
;; --={   - unidade : "ml", "m²", "m³", "un", "kg"                       }=--
;; --={   - layer   : layer onde colocar os objetos medidos              }=--
;; --={   - color   : cor a aplicar aos objetos                          }=--
;; --={   - param   : altura/espessura (m³) ou peso unitário (kg)        }=--
;; --={  Objetos não mensuráveis são ignorados e registados no log.     }=--

(defun ProcessSelection (ss unidade layer color param / i ent obj val v a)
  (setq val 0.0)
  (repeat (setq i (sslength ss))
    (setq ent (ssname ss (setq i (1- i))))
    (setq obj (vlax-ename->vla-object ent))

    ;; --={  Calcular valor do objeto conforme unidade  }=--

    (setq v
      (cond
        ((= unidade "ml") (CalcLength obj))
        ((= unidade "m²") (CalcArea obj))
        ((= unidade "m³") (if (setq a (CalcArea obj)) (* a param)))
        ((= unidade "un") 1.0)
        ((= unidade "kg") param)
        (T nil)
      )
    )

    ;; --={  Acumular e ajustar cor/layer apenas se mensurável  }=--

    (if v
      (progn
        (setq val (+ val v))
        (vla-put-Color obj color)
        (vla-put-Layer obj layer)
      )
      (LogError "Objeto ignorado: não mensurável na unidade escolhida.")
    )
  )
  val
)

;;-----------------------------------------------------------------------------;;
;;              Inicialização VLAX  e verificação de dependências              ;;
;;-----------------------------------------------------------------------------;;

(prompt "\nVerificando suporte a VLAX...")
(if (vl-catch-all-error-p (vl-catch-all-apply 'vlax-get-acad-object '()))
  (progn
    (prompt "\n[Erro] Este ambiente não suporta VLAX. O programa não pode ser executado.")
    (exit)
  )
  (progn
    (vl-load-com)
    (setq *acadApp* (vlax-get-acad-object))
    (setq *doc* (vla-get-ActiveDocument *acadApp*))
    (prompt "\nVLAX carregado e ambiente pronto.")
  )
)

;;-----------------------------------------------------------------------------;;
;;                           Função principal MEDORC                           ;;
;;-----------------------------------------------------------------------------;;

(defun c:MEDORC (/ *error* olderr dcl_id elemento_idx elemento
                 elementos_list unidades_list
                 unidade_idx unidade codigo descricao fator sel
                 ss total quantidade total_final opcao layer altura color
                 filename newfile file)

  ;; --------------------------------------------------------------------------;;
  ;;                          Handler local de erros                           ;;
  ;; --------------------------------------------------------------------------;;

  (defun *error* (msg)
    (if (and msg
             (not (member (strcase msg T)
                          '("function cancelled" "quit / exit abort"))))
      (LogError (strcat "Erro: " msg))
    )
    (vl-catch-all-apply 'vla-EndUndoMark (list *doc*))
    (princ)
  )

  ;; --------------------------------------------------------------------------;;
  ;;                               Carregar DCL                                ;;
  ;; --------------------------------------------------------------------------;;

  (setq dcl_id (load_dialog "medidor_orcamentista.dcl"))
  (if (< dcl_id 0)
    (progn
      (LogError "Não foi possível carregar medidor_orcamentista.dcl. Verifique o Support Path.")
      (exit)
    )
  )
  (if (not (new_dialog "medidor_orcamentista" dcl_id))
    (progn
      (LogError "Não foi possível abrir o diálogo medidor_orcamentista.")
      (unload_dialog dcl_id)
      (exit)
    )
  )

  ;; --------------------------------------------------------------------------;;
  ;;                      Listas de elementos e unidades                       ;;
  ;; --------------------------------------------------------------------------;;

  (setq elementos_list '("Demolições" "Movimento Terras" "Fundações" "Betão" "Alvenarias"
                         "Coberturas" "Cantarias" "Carpintarias" "Serralharias"
                         "Pavimentos" "Paredes" "Tectos" "Pinturas" "Diversos"))
  (setq unidades_list '("ml" "m²" "m³" "un" "kg"))

  ;; --------------------------------------------------------------------------;;
  ;;                       Preencher popup_lists do DCL                        ;;
  ;; --------------------------------------------------------------------------;;

  (start_list "elemento") (mapcar 'add_list elementos_list) (end_list)
  (start_list "unidade")  (mapcar 'add_list unidades_list)  (end_list)

  ;; --------------------------------------------------------------------------;;
  ;;                    Definir valores iniciais do diálogo                    ;;
  ;; --------------------------------------------------------------------------;;

  (set_tile "fator" "1.0")        ; fator por defeito
  (set_tile "selecionar" "1")     ; selecionar objetos por defeito
  (set_tile "elemento" "0")       ; primeiro elemento da lista
  (set_tile "unidade" "0")        ; primeira unidade da lista

  ;; --------------------------------------------------------------------------;;
  ;;                             Botões do diálogo                             ;;
  ;; --------------------------------------------------------------------------;;

  (action_tile "fechar" "(done_dialog 0)")

  ;; --={  Botão Calcular  }=--

  (action_tile "calcular"
    "(progn
       (setq elemento_idx (get_tile \"elemento\"))
       (setq unidade_idx (get_tile \"unidade\"))
       (setq codigo (get_tile \"codigo\"))
       (setq descricao (get_tile \"descricao\"))
       (setq fator (atof (get_tile \"fator\")))
       (setq sel (get_tile \"selecionar\"))
       (done_dialog 1)
    )"
  )

  ;; --={  Botão Limpar  }=--

  (action_tile "limpar"
    "(progn
       (set_tile \"codigo\" \"\")
       (set_tile \"descricao\" \"\")
       (set_tile \"fator\" \"1.0\")
       (set_tile \"selecionar\" \"1\")
       (set_tile \"elemento\" \"0\")
       (set_tile \"unidade\" \"0\")
     )"
  )

  ;; --------------------------------------------------------------------------;;
  ;;                             Executar diálogo                              ;;
  ;; --------------------------------------------------------------------------;;

  (setq opcao (start_dialog))
  (unload_dialog dcl_id)

  ;; --------------------------------------------------------------------------;;
  ;;                         Processar opção escolhida                         ;;
  ;; --------------------------------------------------------------------------;;

  (cond

    ;; --={  Calcular  }=--

    ((= opcao 1)

     ;; --={  Obter valores do diálogo  }=--

     (setq elemento (nth (atoi elemento_idx) elementos_list))
     (setq unidade  (nth (atoi unidade_idx)  unidades_list))

     ;; --={  Garante que o fator mínimo seja 1.0  }=--

     (if (or (not fator) (<= fator 0.0)) (setq fator 1.0))

     ;; --={  Inicializar variável total antes de calcular a medição  }=--

     (setq total 0.0)

     ;; -----------------------------------------------------------------------;;
     ;;                           Seleção de objetos                           ;;
     ;; -----------------------------------------------------------------------;;

     (if (= (atoi sel) 1)
       (progn
         (prompt "\nSelecione os objetos para medir:")
         (setq ss (ssget))

         ;; --={  Sair se não houver objetos selecionados  }=--

         (if (not ss)
           (progn
             (prompt "\nNenhum objeto selecionado. Medição cancelada.")
             (setq total 0.0) ; evita crash
           )
           (progn

             ;; --={  Define layer e cor conforme unidade  }=--

             (cond
               ((= unidade "ml")  (setq layer (EnsureLayer "Medido-comprimentos") color 171))
               ((= unidade "m²")  (setq layer (EnsureLayer "Medido-areas")        color 171))
               ((= unidade "m³")  (setq layer (EnsureLayer "Medido-volumes")      color 171))
               ((= unidade "un")  (setq layer (EnsureLayer "Medido-objectos")     color 171))
               ((= unidade "kg")  (setq layer (EnsureLayer "Medido-pesos")        color 171))
               (T (prompt "\nUnidade não suportada para cálculo"))
             )

             ;; --={  Para volume, pedir altura/espessura  }=--

             (if (= unidade "m³")
               (progn
                 (setq altura (getreal "\nIndique a altura/espessura (m): "))
                 (if (or (not altura) (<= altura 0.0)) (setq altura 1.0))
               )
             )

             ;; --={  Para peso, pedir peso unitário por objeto  }=--

             (if (= unidade "kg")
               (progn
                 (setq altura (getreal "\nIndique o peso unitário (kg/un): "))
                 (if (or (not altura) (<= altura 0.0)) (setq altura 1.0))
               )
             )

             ;; --={  Processar seleção de objetos (com marca de undo)  }=--

             (if layer
               (progn
                 (vla-StartUndoMark *doc*)
                 (setq total (ProcessSelection ss unidade layer color altura))
                 (vla-EndUndoMark *doc*)
               )
             )
           )
         )
       )
     )

     ;; -----------------------------------------------------------------------;;
     ;;                               Resultados                               ;;
     ;; -----------------------------------------------------------------------;;

     (setq quantidade total)
     (setq total_final (* quantidade fator))
     (prompt (strcat "\nMedido (bruto) de " descricao ": " (rtos quantidade 2 2) " " unidade))
     (prompt (strcat "\nTotal (com fator " (rtos fator 2 2) "): " (rtos total_final 2 2) " " unidade))

     ;; -----------------------------------------------------------------------;;
     ;;                           Exportação para CSV                          ;;
     ;; -----------------------------------------------------------------------;;

     (setq filename (strcat (getvar "DWGPREFIX") "medicoes.csv"))
     (setq newfile (or (not (findfile filename)) (= (vl-file-size filename) 0)))
     (setq file (open filename "a"))
     (if (not file)
       (LogError (strcat "Não foi possível escrever em " filename
                         " (ficheiro aberto noutro programa?)"))
       (progn
         (if newfile (write-line "Elemento;Código;Descrição;Unidade;Quantidade;Fator;Total" file))
         (write-line
           (strcat
             (EscapeCSV elemento) ";"   ; Ex: "Paredes"
             (EscapeCSV codigo) ";"     ; Ex: "12345"
             (EscapeCSV descricao) ";"  ; Ex: "Fachada A"
             unidade ";"                ; Ex: "m²"
             (NumCSV quantidade) ";"    ; Quantidade antes do fator
             (NumCSV fator) ";"         ; Fator aplicado
             (NumCSV total_final)       ; Total final com fator
           )
           file
         )
         (close file)
         (prompt (strcat "\nDados exportados para: " filename))
       )
     )
    )

    ;; --={  Fechar  }=--

    ((= opcao 0) (prompt "\nDiálogo fechado."))
  )

  (princ)
)

;;-----------------------------------------------------------------------------;;
;;                      Mensagem Final ao carregar o LISP                      ;;
;;-----------------------------------------------------------------------------;;

(prompt "\nMódulo medidor_orcamentista.lsp v1.1 carregado com sucesso.\nUse MEDORC para executar os comandos.\nCriado por NunchuckCoder.\n")
(princ)
