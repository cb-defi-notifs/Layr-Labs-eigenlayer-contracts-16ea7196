# EigenLayer
Check this out
https://onbjerg.github.io/foundry-book/index.html

## Run Tests

`forge test -vv`

## Run Static Analysis

`solhint 'src/contracts/**/*.sol'`

`slither .`

## Generate Inheritance and Control-Flow Graphs

first install surya

then run

`surya inheritance ./src/contracts/**/*.sol | dot -Tpng > InheritanceGraph.png`

and/or

`surya graph ./src/contracts/middleware/*.sol | dot -Tpng > MiddlewareControlFlowGraph.png`

and/or

`surya mdreport surya_report.md ./src/contracts/**/*.sol`
