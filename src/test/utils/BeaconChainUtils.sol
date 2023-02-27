//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

contract BeaconChainProofUtils{

    bytes32[5] beaconStateMerkleProofForValidators;
    bytes32[] beaconStateMerkleProofForExecutionPayloadHeader;
    bytes32[] validatorMerkleProof;
    bytes32[] withdrawalMerkleProof;
    bytes32[] executionPayloadHeaderProofForWithdrawalProof;
    bytes32[] validatorContainerFields;
    bytes32[] withdrawalContainerFields;

    bytes32[] beaconStateMerkleProofForHistoricalRoots;
    bytes32[] historicalRootsMerkleProof;
    bytes32[] historicalBatchMerkleProof;
    bytes32[] stateRootsMerkleProof;

    bytes32[] beaconStateMerkleProofForStateRoots;
    bytes32[] stateToVerifyMerkleProof;
    bytes32[] blockNumberProof;
    bytes32[] executionPayloadHeaderProof;


    bytes32 beaconStateRoot;
    bytes32 executionPayloadHeaderRoot;
    bytes32 withdrawalListRoot;
    bytes32 withdrawalTreeRoot;
    bytes32 withdrawalRoot;
    bytes32 historicalRootToVerify;
    bytes32 blockNumberRoot;

//this function generates a proof for validator 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f 
    //podManagerAddress for this withdrawal cred: 0x212224d2f2d262cd093ee13240ca4873fccbba3c
    //with an initial deposit of 32 ETH
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py validatorProof 32000000000 32000000000 False False 0
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py validatorProof 32000000000 32000000000 False False 1
    function getInitialDepositProof(uint40 validatorIndex) public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){

        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a0a27649ceb12c195b4fef3d5493d471f7153c7b0b6cf238db3095e1710481a;
        beaconStateMerkleProofForValidators[2] = 0x57b60b0fcc2e03dca91c90913491ebeb2e4c7535ead4c943fe8ede0e2cb8453f;
        beaconStateMerkleProofForValidators[3] = 0xa15b3ec86b16a35669d70a224974edd14f90bcd590d26103251b1aee9e583b3c;
        beaconStateMerkleProofForValidators[4] = 0x264671f54aebf1caeade95ee97316b9b8b5f2f888b1c00a58e9d336997060ab5;
        
        beaconStateRoot = 0x26a6c659291af23ee01c9d14aabf7b9a1a5ae2c2472e07ae3e333e3ac15b7dc1;

        bytes32 validatorTreeRoot;
        bytes32 validatorRoot;

        if(validatorIndex == 0){
  
            validatorContainerFields.push(0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f);
            validatorContainerFields.push(0x01000000000000000000000049c486e3f4303bc11c02f952fe5b08d0ab22d443);
            validatorContainerFields.push(0x0040597307000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0100000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0200000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0300000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0600000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0900000000000000000000000000000000000000000000000000000000000000);
            
            validatorMerkleProof.push(0x22f6350e64f42daadb53165b09eff5aeff289423333fbf4c0e41a4ddbe47dde4);
            validatorMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
            validatorMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
            validatorMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
            validatorMerkleProof.push(0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c);
            validatorMerkleProof.push(0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30);
            validatorMerkleProof.push(0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1);
            validatorMerkleProof.push(0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c);
            validatorMerkleProof.push(0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193);
            validatorMerkleProof.push(0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1);
            validatorMerkleProof.push(0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b);
            validatorMerkleProof.push(0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220);
            validatorMerkleProof.push(0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f);
            validatorMerkleProof.push(0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e);
            validatorMerkleProof.push(0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784);
            validatorMerkleProof.push(0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb);
            validatorMerkleProof.push(0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb);
            validatorMerkleProof.push(0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab);
            validatorMerkleProof.push(0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4);
            validatorMerkleProof.push(0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f);
            validatorMerkleProof.push(0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa);
            validatorMerkleProof.push(0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c);
            validatorMerkleProof.push(0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167);
            validatorMerkleProof.push(0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7);
            validatorMerkleProof.push(0x31206fa80a50bb6abe29085058f16212212a60eec8f049fecb92d8c8e0a84bc0);
            validatorMerkleProof.push(0x21352bfecbeddde993839f614c3dac0a3ee37543f9b412b16199dc158e23b544);
            validatorMerkleProof.push(0x619e312724bb6d7c3153ed9de791d764a366b389af13c58bf8a8d90481a46765);
            validatorMerkleProof.push(0x7cdd2986268250628d0c10e385c58c6191e6fbe05191bcc04f133f2cea72c1c4);
            validatorMerkleProof.push(0x848930bd7ba8cac54661072113fb278869e07bb8587f91392933374d017bcbe1);
            validatorMerkleProof.push(0x8869ff2c22b28cc10510d9853292803328be4fb0e80495e8bb8d271f5b889636);
            validatorMerkleProof.push(0xb5fe28e79f1b850f8658246ce9b6a1e7b49fc06db7143e8fe0b4f2b0c5523a5c);
            validatorMerkleProof.push(0x985e929f70af28d0bdd1a90a808f977f597c7c778c489e98d3bd8910d31ac0f7);
            validatorMerkleProof.push(0xc6f67e02e6e4e1bdefb994c6098953f34636ba2b6ca20a4721d2b26a886722ff);
            validatorMerkleProof.push(0x1c9a7e5ff1cf48b4ad1582d3f4e4a1004f3b20d8c5a2b71387a4254ad933ebc5);
            validatorMerkleProof.push(0x2f075ae229646b6f6aed19a5e372cf295081401eb893ff599b3f9acc0c0d3e7d);
            validatorMerkleProof.push(0x328921deb59612076801e8cd61592107b5c67c79b846595cc6320c395b46362c);
            validatorMerkleProof.push(0xbfb909fdb236ad2411b4e4883810a074b840464689986c3f8a8091827e17c327);
            validatorMerkleProof.push(0x55d8fb3687ba3ba49f342c77f5a1f89bec83d811446e1a467139213d640b6a74);
            validatorMerkleProof.push(0xf7210d4f8e7e1039790e7bf4efa207555a10a6db1dd4b95da313aaa88b88fe76);
            validatorMerkleProof.push(0xad21b516cbc645ffe34ab5de1c8aef8cd4e7f8d2b51e8e1456adc7563cda206f);
            validatorMerkleProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
            
            
            //hash tree root of list of validators
            validatorTreeRoot = 0xc75f788ab2ab0b05910d42b4223fd30c0497f8a6072ef802f4c11ff61a7156c9;
            
            //hash tree root of individual validator container
            validatorRoot = 0x43b889d63df3669586260011ed8034ab7d5b990de961a090e7468ec6d85ab3d7;
        }
        if (validatorIndex == 1){

            validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
            validatorContainerFields[1] = 0x01000000000000000000000049c486e3f4303bc11c02f952fe5b08d0ab22d443;
            validatorContainerFields[2] = 0x0040597307000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[3] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[4] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[5] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
            
            validatorMerkleProof[0] = 0x43b889d63df3669586260011ed8034ab7d5b990de961a090e7468ec6d85ab3d7;
            validatorMerkleProof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
            validatorMerkleProof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
            validatorMerkleProof[3] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
            validatorMerkleProof[4] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
            validatorMerkleProof[5] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
            validatorMerkleProof[6] = 0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1;
            validatorMerkleProof[7] = 0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c;
            validatorMerkleProof[8] = 0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193;
            validatorMerkleProof[9] = 0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1;
            validatorMerkleProof[10] = 0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b;
            validatorMerkleProof[11] = 0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220;
            validatorMerkleProof[12] = 0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f;
            validatorMerkleProof[13] = 0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e;
            validatorMerkleProof[14] = 0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784;
            validatorMerkleProof[15] = 0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb;
            validatorMerkleProof[16] = 0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb;
            validatorMerkleProof[17] = 0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab;
            validatorMerkleProof[18] = 0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4;
            validatorMerkleProof[19] = 0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f;
            validatorMerkleProof[20] = 0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa;
            validatorMerkleProof[21] = 0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c;
            validatorMerkleProof[22] = 0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167;
            validatorMerkleProof[23] = 0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7;
            validatorMerkleProof[24] = 0x31206fa80a50bb6abe29085058f16212212a60eec8f049fecb92d8c8e0a84bc0;
            validatorMerkleProof[25] = 0x21352bfecbeddde993839f614c3dac0a3ee37543f9b412b16199dc158e23b544;
            validatorMerkleProof[26] = 0x619e312724bb6d7c3153ed9de791d764a366b389af13c58bf8a8d90481a46765;
            validatorMerkleProof[27] = 0x7cdd2986268250628d0c10e385c58c6191e6fbe05191bcc04f133f2cea72c1c4;
            validatorMerkleProof[28] = 0x848930bd7ba8cac54661072113fb278869e07bb8587f91392933374d017bcbe1;
            validatorMerkleProof[29] = 0x8869ff2c22b28cc10510d9853292803328be4fb0e80495e8bb8d271f5b889636;
            validatorMerkleProof[30] = 0xb5fe28e79f1b850f8658246ce9b6a1e7b49fc06db7143e8fe0b4f2b0c5523a5c;
            validatorMerkleProof[31] = 0x985e929f70af28d0bdd1a90a808f977f597c7c778c489e98d3bd8910d31ac0f7;
            validatorMerkleProof[32] = 0xc6f67e02e6e4e1bdefb994c6098953f34636ba2b6ca20a4721d2b26a886722ff;
            validatorMerkleProof[33] = 0x1c9a7e5ff1cf48b4ad1582d3f4e4a1004f3b20d8c5a2b71387a4254ad933ebc5;
            validatorMerkleProof[34] = 0x2f075ae229646b6f6aed19a5e372cf295081401eb893ff599b3f9acc0c0d3e7d;
            validatorMerkleProof[35] = 0x328921deb59612076801e8cd61592107b5c67c79b846595cc6320c395b46362c;
            validatorMerkleProof[36] = 0xbfb909fdb236ad2411b4e4883810a074b840464689986c3f8a8091827e17c327;
            validatorMerkleProof[37] = 0x55d8fb3687ba3ba49f342c77f5a1f89bec83d811446e1a467139213d640b6a74;
            validatorMerkleProof[38] = 0xf7210d4f8e7e1039790e7bf4efa207555a10a6db1dd4b95da313aaa88b88fe76;
            validatorMerkleProof[39] = 0xad21b516cbc645ffe34ab5de1c8aef8cd4e7f8d2b51e8e1456adc7563cda206f;
            validatorMerkleProof[40] = 0x0200000000000000000000000000000000000000000000000000000000000000;
            
            
            //hash tree root of list of validators
            validatorTreeRoot = 0xc75f788ab2ab0b05910d42b4223fd30c0497f8a6072ef802f4c11ff61a7156c9;
            
            //hash tree root of individual validator container
            validatorRoot = 0x22f6350e64f42daadb53165b09eff5aeff289423333fbf4c0e41a4ddbe47dde4;

        }

        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);

    }
    //simulates a 16ETH slashing
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py validatorProof 16000000000 16000000000 True True 0
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py validatorProof 16000000000 16000000000 True True 1
    function getSlashedDepositProof(uint40 validatorIndex) public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){

        
        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a0a27649ceb12c195b4fef3d5493d471f7153c7b0b6cf238db3095e1710481a;
        beaconStateMerkleProofForValidators[2] = 0x57b60b0fcc2e03dca91c90913491ebeb2e4c7535ead4c943fe8ede0e2cb8453f;
        beaconStateMerkleProofForValidators[3] = 0xa15b3ec86b16a35669d70a224974edd14f90bcd590d26103251b1aee9e583b3c;
        beaconStateMerkleProofForValidators[4] = 0x264671f54aebf1caeade95ee97316b9b8b5f2f888b1c00a58e9d336997060ab5;
        
        beaconStateRoot = 0x4d37d56a3ade0b302f98a15ab39606b0eaa99a32c3acdceb539d9ab48debdaf6;

         bytes32 validatorTreeRoot;
         bytes32 validatorRoot;
        if(validatorIndex == 0){
            validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
            validatorContainerFields[1] = 0x01000000000000000000000049c486e3f4303bc11c02f952fe5b08d0ab22d443;
            validatorContainerFields[2] = 0x00a0acb903000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[3] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[4] = 0x0200000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[5] = 0x0300000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
            
            validatorMerkleProof[0] = 0x3747dfa31e6f397f7809d77951bcf27d04b590dc17dee871bba4473125fd2150;
            validatorMerkleProof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
            validatorMerkleProof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
            validatorMerkleProof[3] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
            validatorMerkleProof[4] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
            validatorMerkleProof[5] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
            validatorMerkleProof[6] = 0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1;
            validatorMerkleProof[7] = 0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c;
            validatorMerkleProof[8] = 0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193;
            validatorMerkleProof[9] = 0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1;
            validatorMerkleProof[10] = 0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b;
            validatorMerkleProof[11] = 0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220;
            validatorMerkleProof[12] = 0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f;
            validatorMerkleProof[13] = 0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e;
            validatorMerkleProof[14] = 0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784;
            validatorMerkleProof[15] = 0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb;
            validatorMerkleProof[16] = 0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb;
            validatorMerkleProof[17] = 0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab;
            validatorMerkleProof[18] = 0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4;
            validatorMerkleProof[19] = 0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f;
            validatorMerkleProof[20] = 0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa;
            validatorMerkleProof[21] = 0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c;
            validatorMerkleProof[22] = 0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167;
            validatorMerkleProof[23] = 0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7;
            validatorMerkleProof[24] = 0x31206fa80a50bb6abe29085058f16212212a60eec8f049fecb92d8c8e0a84bc0;
            validatorMerkleProof[25] = 0x21352bfecbeddde993839f614c3dac0a3ee37543f9b412b16199dc158e23b544;
            validatorMerkleProof[26] = 0x619e312724bb6d7c3153ed9de791d764a366b389af13c58bf8a8d90481a46765;
            validatorMerkleProof[27] = 0x7cdd2986268250628d0c10e385c58c6191e6fbe05191bcc04f133f2cea72c1c4;
            validatorMerkleProof[28] = 0x848930bd7ba8cac54661072113fb278869e07bb8587f91392933374d017bcbe1;
            validatorMerkleProof[29] = 0x8869ff2c22b28cc10510d9853292803328be4fb0e80495e8bb8d271f5b889636;
            validatorMerkleProof[30] = 0xb5fe28e79f1b850f8658246ce9b6a1e7b49fc06db7143e8fe0b4f2b0c5523a5c;
            validatorMerkleProof[31] = 0x985e929f70af28d0bdd1a90a808f977f597c7c778c489e98d3bd8910d31ac0f7;
            validatorMerkleProof[32] = 0xc6f67e02e6e4e1bdefb994c6098953f34636ba2b6ca20a4721d2b26a886722ff;
            validatorMerkleProof[33] = 0x1c9a7e5ff1cf48b4ad1582d3f4e4a1004f3b20d8c5a2b71387a4254ad933ebc5;
            validatorMerkleProof[34] = 0x2f075ae229646b6f6aed19a5e372cf295081401eb893ff599b3f9acc0c0d3e7d;
            validatorMerkleProof[35] = 0x328921deb59612076801e8cd61592107b5c67c79b846595cc6320c395b46362c;
            validatorMerkleProof[36] = 0xbfb909fdb236ad2411b4e4883810a074b840464689986c3f8a8091827e17c327;
            validatorMerkleProof[37] = 0x55d8fb3687ba3ba49f342c77f5a1f89bec83d811446e1a467139213d640b6a74;
            validatorMerkleProof[38] = 0xf7210d4f8e7e1039790e7bf4efa207555a10a6db1dd4b95da313aaa88b88fe76;
            validatorMerkleProof[39] = 0xad21b516cbc645ffe34ab5de1c8aef8cd4e7f8d2b51e8e1456adc7563cda206f;
            validatorMerkleProof[40] = 0x0200000000000000000000000000000000000000000000000000000000000000;
            
            
            //hash tree root of list of validators
            validatorTreeRoot = 0x8ebf489ee93ffec8841959ce32d03b7c9f9802c7c3fe60fbe08642733cc96bbe;
            
            //hash tree root of individual validator container
            validatorRoot = 0xdb9a2ad5386188dd719a3f63a45bd5ec249fb83c7d32370e29ea3df7a9ff88f5;
        }

        if (validatorIndex == 1){
            validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
            validatorContainerFields[1] = 0x01000000000000000000000049c486e3f4303bc11c02f952fe5b08d0ab22d443;
            validatorContainerFields[2] = 0x00a0acb903000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[3] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[4] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[5] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
            
            validatorMerkleProof[0] = 0xdb9a2ad5386188dd719a3f63a45bd5ec249fb83c7d32370e29ea3df7a9ff88f5;
            validatorMerkleProof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
            validatorMerkleProof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
            validatorMerkleProof[3] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
            validatorMerkleProof[4] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
            validatorMerkleProof[5] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
            validatorMerkleProof[6] = 0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1;
            validatorMerkleProof[7] = 0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c;
            validatorMerkleProof[8] = 0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193;
            validatorMerkleProof[9] = 0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1;
            validatorMerkleProof[10] = 0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b;
            validatorMerkleProof[11] = 0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220;
            validatorMerkleProof[12] = 0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f;
            validatorMerkleProof[13] = 0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e;
            validatorMerkleProof[14] = 0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784;
            validatorMerkleProof[15] = 0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb;
            validatorMerkleProof[16] = 0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb;
            validatorMerkleProof[17] = 0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab;
            validatorMerkleProof[18] = 0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4;
            validatorMerkleProof[19] = 0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f;
            validatorMerkleProof[20] = 0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa;
            validatorMerkleProof[21] = 0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c;
            validatorMerkleProof[22] = 0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167;
            validatorMerkleProof[23] = 0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7;
            validatorMerkleProof[24] = 0x31206fa80a50bb6abe29085058f16212212a60eec8f049fecb92d8c8e0a84bc0;
            validatorMerkleProof[25] = 0x21352bfecbeddde993839f614c3dac0a3ee37543f9b412b16199dc158e23b544;
            validatorMerkleProof[26] = 0x619e312724bb6d7c3153ed9de791d764a366b389af13c58bf8a8d90481a46765;
            validatorMerkleProof[27] = 0x7cdd2986268250628d0c10e385c58c6191e6fbe05191bcc04f133f2cea72c1c4;
            validatorMerkleProof[28] = 0x848930bd7ba8cac54661072113fb278869e07bb8587f91392933374d017bcbe1;
            validatorMerkleProof[29] = 0x8869ff2c22b28cc10510d9853292803328be4fb0e80495e8bb8d271f5b889636;
            validatorMerkleProof[30] = 0xb5fe28e79f1b850f8658246ce9b6a1e7b49fc06db7143e8fe0b4f2b0c5523a5c;
            validatorMerkleProof[31] = 0x985e929f70af28d0bdd1a90a808f977f597c7c778c489e98d3bd8910d31ac0f7;
            validatorMerkleProof[32] = 0xc6f67e02e6e4e1bdefb994c6098953f34636ba2b6ca20a4721d2b26a886722ff;
            validatorMerkleProof[33] = 0x1c9a7e5ff1cf48b4ad1582d3f4e4a1004f3b20d8c5a2b71387a4254ad933ebc5;
            validatorMerkleProof[34] = 0x2f075ae229646b6f6aed19a5e372cf295081401eb893ff599b3f9acc0c0d3e7d;
            validatorMerkleProof[35] = 0x328921deb59612076801e8cd61592107b5c67c79b846595cc6320c395b46362c;
            validatorMerkleProof[36] = 0xbfb909fdb236ad2411b4e4883810a074b840464689986c3f8a8091827e17c327;
            validatorMerkleProof[37] = 0x55d8fb3687ba3ba49f342c77f5a1f89bec83d811446e1a467139213d640b6a74;
            validatorMerkleProof[38] = 0xf7210d4f8e7e1039790e7bf4efa207555a10a6db1dd4b95da313aaa88b88fe76;
            validatorMerkleProof[39] = 0xad21b516cbc645ffe34ab5de1c8aef8cd4e7f8d2b51e8e1456adc7563cda206f;
            validatorMerkleProof[40] = 0x0200000000000000000000000000000000000000000000000000000000000000;
            
            
            //hash tree root of list of validators
            validatorTreeRoot = 0x8ebf489ee93ffec8841959ce32d03b7c9f9802c7c3fe60fbe08642733cc96bbe;
            
            //hash tree root of individual validator container
            validatorRoot = 0x3747dfa31e6f397f7809d77951bcf27d04b590dc17dee871bba4473125fd2150;
        }

        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);
    }

    function getFullWithdrawalValidatorProof() public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32) {
        bytes32 validatorTreeRoot;
        bytes32 validatorRoot;

        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a0a27649ceb12c195b4fef3d5493d471f7153c7b0b6cf238db3095e1710481a;
        beaconStateMerkleProofForValidators[2] = 0x57b60b0fcc2e03dca91c90913491ebeb2e4c7535ead4c943fe8ede0e2cb8453f;
        beaconStateMerkleProofForValidators[3] = 0xa15b3ec86b16a35669d70a224974edd14f90bcd590d26103251b1aee9e583b3c;
        beaconStateMerkleProofForValidators[4] = 0x264671f54aebf1caeade95ee97316b9b8b5f2f888b1c00a58e9d336997060ab5;
        
        beaconStateRoot = 0x85ff1a7bff2d74d99a6152755db556f0535d38105944c85c159ee5548c3549d5;
        
        validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
        validatorContainerFields[1] = 0x01000000000000000000000049c486e3f4303bc11c02f952fe5b08d0ab22d443;
        validatorContainerFields[2] = 0x00fa954f07000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[3] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[4] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[5] = 0x0100000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[7] = 0x1400000000000000000000000000000000000000000000000000000000000000;
        
        validatorMerkleProof[0] = 0x7d62a1e988b00b7c363600711cd3bff1a2b8f6408c232d0b703a36bee15a32bf;
        validatorMerkleProof[1] = 0x5aea1fc33af4dcd3762ad871a506ab232e12ba56bc08aff438a7ffe68802f326;
        validatorMerkleProof[2] = 0x632dba8f77f6fb96b669d3d6b49357de4f4d91d6b5e50f4703189187b37f8e5f;
        validatorMerkleProof[3] = 0xac9b9ce65a4a2e15c455665b66176c99320162fd7a58b235f65b9d9664c7c562;
        validatorMerkleProof[4] = 0x28e464cd5a47060aea5cbd04d2878f1476a05750971399895fe64c255cca5e03;
        validatorMerkleProof[5] = 0xe8617d6868d0fa76a2ef838361f163bdfee3b860cfb7300a79f079480c267f3e;
        validatorMerkleProof[6] = 0x5142bc047177f83f65bb93cbfc891052c0fff75f2cb7e0b16195eae749d2c5a7;
        validatorMerkleProof[7] = 0x107bdec15614d8dc3e679080a3b413ff09cea2fc3a2a6ea6971c59f9cef2be6f;
        validatorMerkleProof[8] = 0x643dbe7e3e8970a50632a30eff20ab7f028311b3b2a8fe125b4101c373b4d32c;
        validatorMerkleProof[9] = 0x326d411d7d5e367076d1b7ce563bbf530c9e662d334c080814b4b3513984711f;
        validatorMerkleProof[10] = 0xc73da57244a872b6972cb27f4969f95bb4b9333a1284bd674c650c0697c6733c;
        validatorMerkleProof[11] = 0x4701bd1561ec1f8a79eedb37a43f1a51dd21696aba8ffdb97385ab4820ea3315;
        validatorMerkleProof[12] = 0x2943b687c3dacb334ed5638f6abae29630bd67696143a3f439a2c47173a926f0;
        validatorMerkleProof[13] = 0x64f19fe370519a0fc09c957b826200885106684b983f041268dbebafcc346fe3;
        validatorMerkleProof[14] = 0x69c5ce6a50fc785bf9ce44b95fd8ffb74ce5360fb6e9b610392520a99c203eb1;
        validatorMerkleProof[15] = 0x4222b343fa462757618b167557f0ab7e9db82d0c95e41480afd3c63694cd48cf;
        validatorMerkleProof[16] = 0x564bc4ada85df0f0933a01c63bb3e99c0117c3621f4cf258ad7f1ac90fb6b78a;
        validatorMerkleProof[17] = 0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab;
        validatorMerkleProof[18] = 0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4;
        validatorMerkleProof[19] = 0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f;
        validatorMerkleProof[20] = 0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa;
        validatorMerkleProof[21] = 0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c;
        validatorMerkleProof[22] = 0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167;
        validatorMerkleProof[23] = 0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7;
        validatorMerkleProof[24] = 0x31206fa80a50bb6abe29085058f16212212a60eec8f049fecb92d8c8e0a84bc0;
        validatorMerkleProof[25] = 0x21352bfecbeddde993839f614c3dac0a3ee37543f9b412b16199dc158e23b544;
        validatorMerkleProof[26] = 0x619e312724bb6d7c3153ed9de791d764a366b389af13c58bf8a8d90481a46765;
        validatorMerkleProof[27] = 0x7cdd2986268250628d0c10e385c58c6191e6fbe05191bcc04f133f2cea72c1c4;
        validatorMerkleProof[28] = 0x848930bd7ba8cac54661072113fb278869e07bb8587f91392933374d017bcbe1;
        validatorMerkleProof[29] = 0x8869ff2c22b28cc10510d9853292803328be4fb0e80495e8bb8d271f5b889636;
        validatorMerkleProof[30] = 0xb5fe28e79f1b850f8658246ce9b6a1e7b49fc06db7143e8fe0b4f2b0c5523a5c;
        validatorMerkleProof[31] = 0x985e929f70af28d0bdd1a90a808f977f597c7c778c489e98d3bd8910d31ac0f7;
        validatorMerkleProof[32] = 0xc6f67e02e6e4e1bdefb994c6098953f34636ba2b6ca20a4721d2b26a886722ff;
        validatorMerkleProof[33] = 0x1c9a7e5ff1cf48b4ad1582d3f4e4a1004f3b20d8c5a2b71387a4254ad933ebc5;
        validatorMerkleProof[34] = 0x2f075ae229646b6f6aed19a5e372cf295081401eb893ff599b3f9acc0c0d3e7d;
        validatorMerkleProof[35] = 0x328921deb59612076801e8cd61592107b5c67c79b846595cc6320c395b46362c;
        validatorMerkleProof[36] = 0xbfb909fdb236ad2411b4e4883810a074b840464689986c3f8a8091827e17c327;
        validatorMerkleProof[37] = 0x55d8fb3687ba3ba49f342c77f5a1f89bec83d811446e1a467139213d640b6a74;
        validatorMerkleProof[38] = 0xf7210d4f8e7e1039790e7bf4efa207555a10a6db1dd4b95da313aaa88b88fe76;
        validatorMerkleProof[39] = 0xad21b516cbc645ffe34ab5de1c8aef8cd4e7f8d2b51e8e1456adc7563cda206f;
        validatorMerkleProof[40] = 0xa286010000000000000000000000000000000000000000000000000000000000;
        
        
        //hash tree root of list of validators
        validatorTreeRoot = 0xab8be6505017421cf95b936000faeddb0c5e67631852d602485f7dd21ea97224;
        
        //hash tree root of individual validator container
        validatorRoot = 0x7b829b073e0af88695da007b859e6f3f1b94c85db6370870ecede445bddbe6b2;
            
        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);
    }

}
