const Web3 = require('web3')
const web3 = new Web3("https://eth-mainnet.alchemyapi.io/v2/YvoE-0g_16gIOqcH6axberSLkJ8FseoL")
web3.eth.getProof(
    "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    ["0x0000000000000000000000000000000000000000000000000000000000000000"],
    "latest"
).then((x) => {
    console.log(x)
    console.log(x.storageProof[0].proof)
    console.log()
});