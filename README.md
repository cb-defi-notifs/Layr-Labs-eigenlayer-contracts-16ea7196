# EigenLayr
Check this out
https://onbjerg.github.io/foundry-book/index.html

## Run Tests

`forge test -vv`

## Run Static Analysis

`solhint 'src/contracts/**/*.sol'`

`slither .`

## Generate Inheritance and Control-Flow Graph

first install surya, then run
`surya inheritance ./src/contracts/**/*.sol | dot -Tpng > InheritanceGraph.png`