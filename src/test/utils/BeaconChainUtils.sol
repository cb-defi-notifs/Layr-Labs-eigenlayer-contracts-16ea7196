//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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
    //with an initial deposit of 32 ETH
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py validatorProof 32000000000 32000000000 False False 0
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py validatorProof 32000000000 32000000000 False False 1
    function getInitialDepositProof(uint40 validatorIndex) public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){

        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a0a27649ceb12c195b4fef3d5493d471f7153c7b0b6cf238db3095e1710481a;
        beaconStateMerkleProofForValidators[2] = 0x57b60b0fcc2e03dca91c90913491ebeb2e4c7535ead4c943fe8ede0e2cb8453f;
        beaconStateMerkleProofForValidators[3] = 0xa15b3ec86b16a35669d70a224974edd14f90bcd590d26103251b1aee9e583b3c;
        beaconStateMerkleProofForValidators[4] = 0x264671f54aebf1caeade95ee97316b9b8b5f2f888b1c00a58e9d336997060ab5;
        
        beaconStateRoot = 0xb45dd20e641694b2465610f1a6b1891f312fedf2baf67ee0243c58f1a5262bba;

        bytes32 validatorTreeRoot;
        bytes32 validatorRoot;

        if(validatorIndex == 0){
  
            validatorContainerFields.push(0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f);
            validatorContainerFields.push(0x01000000000000000000000093939caed8a5a52e4dda47b64579ce1a5c8549dc);
            validatorContainerFields.push(0x0040597307000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0100000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0200000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0300000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0600000000000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0900000000000000000000000000000000000000000000000000000000000000);
            
            validatorMerkleProof.push(0xfe3f978f8be10d5713f3548ee71dfbacabb0763433fea9080b7e71e87bd9cd5b);
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
            validatorTreeRoot = 0x5c34eacbfb500468bc4c8872bdef789195f7ecc7e3ce693517d2295bfc2cae73;
            
            //hash tree root of individual validator container
            validatorRoot = 0x4cb86c67982035de1668f5b4f588f743290901e11f91cb6cacfe940a98d8fb57;
        }
        if (validatorIndex == 1){

            validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
            validatorContainerFields[1] = 0x01000000000000000000000093939caed8a5a52e4dda47b64579ce1a5c8549dc;
            validatorContainerFields[2] = 0x0040597307000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[3] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[4] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[5] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
            
            validatorMerkleProof[0] = 0x4cb86c67982035de1668f5b4f588f743290901e11f91cb6cacfe940a98d8fb57;
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
            validatorTreeRoot = 0x5c34eacbfb500468bc4c8872bdef789195f7ecc7e3ce693517d2295bfc2cae73;
            
            //hash tree root of individual validator container
            validatorRoot = 0xfe3f978f8be10d5713f3548ee71dfbacabb0763433fea9080b7e71e87bd9cd5b;

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
        
        beaconStateRoot = 0xd3e0a14d0c42d0df3bfdf58ae637c39dd473b6417c513ba51ea2a482bb4a16ed;

         bytes32 validatorTreeRoot;
         bytes32 validatorRoot;
        if(validatorIndex == 0){
            validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
            validatorContainerFields[1] = 0x01000000000000000000000093939caed8a5a52e4dda47b64579ce1a5c8549dc;
            validatorContainerFields[2] = 0x00a0acb903000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[3] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[4] = 0x0200000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[5] = 0x0300000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
            
            validatorMerkleProof[0] = 0xe36ac8adc957eed2f4b757ee5989dfb8106c451200fb69a6260c567e7278f3b6;
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
            validatorTreeRoot = 0xbf7805a8d3bf9c9c313b62aa7c05398d0d5ef53e353fca7037e59bfa6d9fe441;
            
            //hash tree root of individual validator container
            validatorRoot = 0xd76c62693b5606cb03975ef772de1e215b61a42d93d816bca036795247949010;
        }

        if (validatorIndex == 1){
            validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
            validatorContainerFields[1] = 0x01000000000000000000000093939caed8a5a52e4dda47b64579ce1a5c8549dc;
            validatorContainerFields[2] = 0x00a0acb903000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[3] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[4] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[5] = 0x0100000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
            validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
            
            validatorMerkleProof[0] = 0xd76c62693b5606cb03975ef772de1e215b61a42d93d816bca036795247949010;
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
            validatorTreeRoot = 0xbf7805a8d3bf9c9c313b62aa7c05398d0d5ef53e353fca7037e59bfa6d9fe441;
            
            //hash tree root of individual validator container
            validatorRoot = 0xe36ac8adc957eed2f4b757ee5989dfb8106c451200fb69a6260c567e7278f3b6;
        }

        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);
    }

    //generated with /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py withdrawalProof 31400000000 31400000000 0
    function getWithdrawalProofsWithBlockNumber() public returns(bytes32, bytes32, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory, bytes32[] memory) {

        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x00fa954f07000000000000000000000000000000000000000000000000000000);
        
        beaconStateRoot = 0x41abbc134575ff7d3f69e2b944f35366e448729f52932d785568cf2a75af9127;
        blockNumberRoot = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        executionPayloadHeaderRoot = 0xe0b9dc07dc5921c0220612c160ff0142ffaa3f9cc38f752bd7ade38beb082d21;
        
        executionPayloadHeaderProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0x8a023a9e4affbb255a6b48ae85cc4a7d1a1b9e8e6809fe9e48535c01c1fc071a);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0x2e9e44d45a41f0e0da340441f66894d25a002b0e18361bc156963eab8a62c597);
        executionPayloadHeaderProof.push(0x828490a3bd4de4b730540849b5b5974f86af18b0711dcc69cdf1a0ca0df16ed3);
        executionPayloadHeaderProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        executionPayloadHeaderProof.push(0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c);
        executionPayloadHeaderProof.push(0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30);
        executionPayloadHeaderProof.push(0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1);
        executionPayloadHeaderProof.push(0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c);
        executionPayloadHeaderProof.push(0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193);
        executionPayloadHeaderProof.push(0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1);
        executionPayloadHeaderProof.push(0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b);
        executionPayloadHeaderProof.push(0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220);
        executionPayloadHeaderProof.push(0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f);
        executionPayloadHeaderProof.push(0xa75b0948052d091c3cb41f390e76fc7cb987b787bf4063c563e09266a357dea1);
        executionPayloadHeaderProof.push(0xac8bcfe8919014340a31b81e1b8cc5efecc8df04f0303fdce86903d24a7aa67a);
        executionPayloadHeaderProof.push(0x5a374976a34347c1b56054efcf4f2029c6ec8d34b55385d608475a533a2cce37);
        executionPayloadHeaderProof.push(0x497b79d19c79fea8029e9c91e3d41c8122a16393b6ff5e5a8e75b9bb26de5e9e);
        executionPayloadHeaderProof.push(0x264671f54aebf1caeade95ee97316b9b8b5f2f888b1c00a58e9d336997060ab5);
        
        blockNumberProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        blockNumberProof.push(0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6);
        blockNumberProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        blockNumberProof.push(0x537fb2141ba3616b89a1c9695e401120d1a703801a8ed085d3418d10a99e9f06);
        
        withdrawalMerkleProof.push(0xdb5d6cdcec5c9516578f2af13b311de975ba6102376a47c9714228aa0f6aed8b);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        withdrawalMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        withdrawalMerkleProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0x7e716846ef6aade1cdc8586ab65a207f2e94e03bbdcd320da73f2307e872a0fb);
        withdrawalMerkleProof.push(0x83ff25f2887e963d4d555834b7a0a9db85633d8d8f095e645d14d652d26aabb3);


        return(beaconStateRoot, executionPayloadHeaderRoot, blockNumberRoot, executionPayloadHeaderProof, blockNumberProof, withdrawalMerkleProof, withdrawalContainerFields);
    }

    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py withdrawalProof 1000000000 31400000000 0
    function getSmallInsufficientFullWithdrawalProof() public returns(bytes32, bytes32, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory, bytes32[] memory) {
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x00ca9a3b00000000000000000000000000000000000000000000000000000000);
        
        beaconStateRoot = 0xcae08d9fb5edd4535e7332030756740033b8114fa79e8778f1a941b65d382cef;
        blockNumberRoot = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        executionPayloadHeaderRoot = 0x36e1efd39a152d4bee7beac01974af1d04f878d9d0bfb637036d974606c7174a;
        
        executionPayloadHeaderProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0x8a023a9e4affbb255a6b48ae85cc4a7d1a1b9e8e6809fe9e48535c01c1fc071a);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0x2e9e44d45a41f0e0da340441f66894d25a002b0e18361bc156963eab8a62c597);
        executionPayloadHeaderProof.push(0x828490a3bd4de4b730540849b5b5974f86af18b0711dcc69cdf1a0ca0df16ed3);
        executionPayloadHeaderProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        executionPayloadHeaderProof.push(0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c);
        executionPayloadHeaderProof.push(0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30);
        executionPayloadHeaderProof.push(0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1);
        executionPayloadHeaderProof.push(0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c);
        executionPayloadHeaderProof.push(0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193);
        executionPayloadHeaderProof.push(0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1);
        executionPayloadHeaderProof.push(0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b);
        executionPayloadHeaderProof.push(0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220);
        executionPayloadHeaderProof.push(0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f);
        executionPayloadHeaderProof.push(0xa75b0948052d091c3cb41f390e76fc7cb987b787bf4063c563e09266a357dea1);
        executionPayloadHeaderProof.push(0x83d990d76397c1651e3d53f79738c65ffec766d161488a324af22362b268cd62);
        executionPayloadHeaderProof.push(0x5a374976a34347c1b56054efcf4f2029c6ec8d34b55385d608475a533a2cce37);
        executionPayloadHeaderProof.push(0x497b79d19c79fea8029e9c91e3d41c8122a16393b6ff5e5a8e75b9bb26de5e9e);
        executionPayloadHeaderProof.push(0xa2e718950d8c7da330016805ff9e67372b22e85b5ac73adc4accf31120b9a8cb);
        
        blockNumberProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        blockNumberProof.push(0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6);
        blockNumberProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        blockNumberProof.push(0x69df0cf9f139fa0b35578f01c0f9f2f706420988a4a6cadf56982b1590a69ce4);
        
        withdrawalMerkleProof.push(0xdb5d6cdcec5c9516578f2af13b311de975ba6102376a47c9714228aa0f6aed8b);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        withdrawalMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        withdrawalMerkleProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0x7e716846ef6aade1cdc8586ab65a207f2e94e03bbdcd320da73f2307e872a0fb);
        withdrawalMerkleProof.push(0x83ff25f2887e963d4d555834b7a0a9db85633d8d8f095e645d14d652d26aabb3);

        return(beaconStateRoot, executionPayloadHeaderRoot, blockNumberRoot, executionPayloadHeaderProof, blockNumberProof, withdrawalMerkleProof, withdrawalContainerFields);
    }
    // /Users/sidu/consensus-specs/venv/bin/python /Users/sidu/beaconchain-proofs/capella/merkleization_FINAL.py withdrawalProof 31000000000 31400000000 0
    function getLargeInsufficientFullWithdrawalProof() public returns(bytes32, bytes32, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory, bytes32[] memory) {
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0076be3707000000000000000000000000000000000000000000000000000000);
        
        beaconStateRoot = 0x2b467e28891ced911c9e8a9c140d004eff4411a217454cf6ea5bfba104045c5d;
        blockNumberRoot = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        executionPayloadHeaderRoot = 0x256cbafc330d9778a2948927d437b57d95a412ce61e5f35a8e2db477a70c3c62;
        
        executionPayloadHeaderProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0x8a023a9e4affbb255a6b48ae85cc4a7d1a1b9e8e6809fe9e48535c01c1fc071a);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0x2e9e44d45a41f0e0da340441f66894d25a002b0e18361bc156963eab8a62c597);
        executionPayloadHeaderProof.push(0x828490a3bd4de4b730540849b5b5974f86af18b0711dcc69cdf1a0ca0df16ed3);
        executionPayloadHeaderProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        executionPayloadHeaderProof.push(0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c);
        executionPayloadHeaderProof.push(0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30);
        executionPayloadHeaderProof.push(0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1);
        executionPayloadHeaderProof.push(0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c);
        executionPayloadHeaderProof.push(0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193);
        executionPayloadHeaderProof.push(0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1);
        executionPayloadHeaderProof.push(0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b);
        executionPayloadHeaderProof.push(0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220);
        executionPayloadHeaderProof.push(0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f);
        executionPayloadHeaderProof.push(0xa75b0948052d091c3cb41f390e76fc7cb987b787bf4063c563e09266a357dea1);
        executionPayloadHeaderProof.push(0x3562491490b9d49982e81254c2ac1a73bcf1c6491d48e2ba1bb5d4e8e1dfca7b);
        executionPayloadHeaderProof.push(0x5a374976a34347c1b56054efcf4f2029c6ec8d34b55385d608475a533a2cce37);
        executionPayloadHeaderProof.push(0x497b79d19c79fea8029e9c91e3d41c8122a16393b6ff5e5a8e75b9bb26de5e9e);
        executionPayloadHeaderProof.push(0xc3208664d0c3d1058bdf0fb59f07e8890479939b81b2ec9337361530a69d48d1);
        
        blockNumberProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        blockNumberProof.push(0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6);
        blockNumberProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        blockNumberProof.push(0x7aa12a88131a78d9a77801d94d22084c91949284815b6ec794afe4286a7996c0);
        
        withdrawalMerkleProof.push(0xdb5d6cdcec5c9516578f2af13b311de975ba6102376a47c9714228aa0f6aed8b);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        withdrawalMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        withdrawalMerkleProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0x7e716846ef6aade1cdc8586ab65a207f2e94e03bbdcd320da73f2307e872a0fb);
        withdrawalMerkleProof.push(0x83ff25f2887e963d4d555834b7a0a9db85633d8d8f095e645d14d652d26aabb3);


        return(beaconStateRoot, executionPayloadHeaderRoot, blockNumberRoot, executionPayloadHeaderProof, blockNumberProof, withdrawalMerkleProof, withdrawalContainerFields);
    }
}