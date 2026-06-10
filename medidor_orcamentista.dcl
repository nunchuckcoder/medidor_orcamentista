// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Osvaldo Cipriano (github.com/nunchuckcoder)

medidor_orcamentista : dialog {
    label = "Medidor Orçamentista - v1.1";
    : row {
        : column {
            : text { label = "Elemento:"; }
            : popup_list { key = "elemento"; }

            : text { label = "Código:"; }
            : edit_box { key = "codigo"; width = 20; }

            : text { label = "Descrição:"; }
            : edit_box { key = "descricao"; width = 30; }
        }
        : column {
            : text { label = "Unidade:"; }
            : popup_list { key = "unidade"; }

            : text { label = "Fator multiplicador:"; }
            : edit_box { key = "fator"; width = 10; }

            : text { label = ""; }
            : toggle { key = "selecionar"; label = "Indicar objetos no desenho"; }
        }
    }

    : row {
        : button { key = "calcular"; label = "Calcular"; }
        : button { key = "limpar"; label = "Limpar"; }
        : button { key = "fechar"; label = "Fechar"; is_cancel = true; }
    }
}
