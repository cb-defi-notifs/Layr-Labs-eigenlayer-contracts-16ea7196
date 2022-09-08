#!/usr/bin/env python

import subprocess

template = """forge create --rpc-url {socket_val} --private-key {private_key_val} {src_val}"""
template_args = """forge create --rpc-url {socket_val} --constructor-args {args_val} --private-key {private_key_val} {src_val}"""

socket = "http://0.0.0.0:8546"
private_key = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

def deploy_contract(contract, args):
    if len(args) == 0:
        deploy_cmd = template.format(
            socket_val=socket,
            private_key_val=private_key,
            src_val=contract,
        )
        print(deploy_cmd)
        result = subprocess.run(deploy_cmd.split(' '), stdout=subprocess.PIPE)
        # print(result.stdout)
        return parse_output(str(result.stdout))
    else:
        args_ = ' '.join(args)
        deploy_cmd = template_args.format(
            socket_val=socket,
            private_key_val=private_key,
            src_val=contract,
            args_val=args_,
        )
        # print("deploy cmd ", deploy_cmd)

        result = subprocess.run(deploy_cmd.split(' '), stdout=subprocess.PIPE)
        # print("with arg stdout", result.stdout)
        return parse_output(str(result.stdout))


def parse_output(out):
    tokens = out.split(" ")
    info = []
    for t in tokens:
        if t[:2] == "0x":
            r = t.split("\\n")
            info.append(r[0])
    # the second 0x... is deployed address
    # print("info", info)
    return info[1]

###    Deploy the whole contract
deployer_addr = deploy_contract("src/contracts/setup/Deployer.sol:EigenLayrDeployer", [])
print(deployer_addr)

#  Deploy deposit
# deposit_addr  = deploy_contract("src/contracts/mock/DepositContract.sol:DepositContract", [])
# print("deposit_addr",  deposit_addr, '\n')

# deployer_addr = deploy_contract("src/contracts/mock/EigenLayrDeployer.sol:EigenLayrDeployer", [])
# print("deployer_addr", deployer_addr, '\n')

# eigen_addr    = deploy_contract("src/contracts/core/Eigen.sol:Eigen",                     [deployer_addr])
# print("eigen_addr",    eigen_addr, '\n')

# consensusLayerDepositRoot = '0x9c4bad94539254189bb933df374b1c2eb9096913a1f6a3326b84133d2b9b9bad'
# eigen_layr_deposit_addr = deploy_contract("src/contracts/core/EigenLayrDeposit.sol:EigenLayrDeposit",                     [consensusLayerDepositRoot, eigen_addr])
# print("eigen_layr_deposit_addr", eigen_layr_deposit_addr, '\n')

# delegation_addr = deploy_contract("src/contracts/core/EigenLayrDelegation.sol:EigenLayrDelegation", [])
# print("delegation_addr", delegation_addr, '\n')

# investment_addr = deploy_contract("src/contracts/investment/InvestmentManager.sol:InvestmentManager", [eigen_addr, delegation_addr])
# print("investment_addr", investment_addr, '\n')

# # slasher_addr    = deploy_contract("src/contracts/investment/Slasher.sol:Slasher", [investment_addr]);
# service_factory_addr = deploy_contract("src/contracts/middleware/ServiceFactory.sol:ServiceFactory", [investment_addr])
# print("service_factory_addr", service_factory_addr, '\n')



