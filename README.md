# EigenLayer

## Table of Contents  
* [Introduction](#introduction)
* [Installation](#installation)
* [EigenLayer Technical Specification](docs/EigenLayer-tech-spec.md)
* [EigenDA Contracts Technical Specification](docs/EigenDA-contracts-tech-spec.md)
* [An Introduction to Proofs of Custody](docs/Proofs-of-Custody.md)
* [Low Degree Challenge Deep Dive](docs/LowDegreenessChallenge-overview.md)
* [EigenLayer Withdrawal Flow](docs/EigenLayer-withdrawal-flow.md)
* [EigenDA Registration Flow](docs/DataLayr-registration-flow.md)

<a name="introduction"/></a>
## Introduction
EigenLayer (formerly 'EigenLayr') is a set of smart contracts deployed on Ethereum that enable restaking of assets to secure new services.
EigenDA (formerly 'DataLayr') is a Data Availability network built on top of EigenLayer.
At present, this repository contains *both* the contracts for EigenLayer *and* the contracts for EigenDA; additionally, the EigenDA contracts are built on top of general "middleware" contracts, designed to be reuseable across different applications built on top of EigenLayer.

Click the links in the Table of Contents above to access more specific documentation!

<a name="installation"/></a>
## Installation

`foundry up`

See the [Foundry Docs](https://book.getfoundry.sh/) for more info.

### Run Tests

`forge test -vv`

### Run Static Analysis

`solhint 'src/contracts/**/*.sol'`

`slither .`

### Generate Inheritance and Control-Flow Graphs

first install surya

then run

`surya inheritance ./src/contracts/**/*.sol | dot -Tpng > InheritanceGraph.png`

and/or

`surya graph ./src/contracts/middleware/*.sol | dot -Tpng > MiddlewareControlFlowGraph.png`

and/or

`surya mdreport surya_report.md ./src/contracts/**/*.sol`
