/// description: If request was fulfilled for the none N it means that current nonce N' must be N' >= N
rule internalNonceUpperboundsRequestFulfillmentNonce(address guardian, bytes knotId, uint256 nonce, method f, env e)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require knotId.length <= 7;
    require nonce <= 10000000000;
    require knotIdToInternalNonce(knotId) <= 10000000000;

    require getDecryptionRequestTracker(e, guardian, knotId, nonce) == true => knotIdToInternalNonce(knotId) >= nonce;

    invokeParametricByBlsKey(e, f, knotId);

    assert getDecryptionRequestTracker(e, guardian, knotId, nonce) == true => knotIdToInternalNonce(knotId) >= nonce;
}