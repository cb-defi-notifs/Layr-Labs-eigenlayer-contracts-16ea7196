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
    function getInitialDepositProof(uint40 validatorIndex) public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){

        beaconStateMerkleProofForValidators[0] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        beaconStateMerkleProofForValidators[1] = (0x8a7c6aed738e0a0cf25ebb8c5b4da41173285b41451674890a0ca5a100c2d3c9);
        beaconStateMerkleProofForValidators[2] = (0xd63afe2579fd495c87de3b1dc9dded10c6e65b1a717a4efed9e826b969e2a6d9);
        beaconStateMerkleProofForValidators[3] = (0x086ef90e3db0073ad2f8b2e6b38653d726e850fde26859dd881da1ac523598f0);
        beaconStateMerkleProofForValidators[4] = (0x1260718cd540a187a9dcff9f4d39116cdc1a0aed8a94fbe7a69fb87eae747be5);

        beaconStateRoot = 0xccc2f0f711fceb7a06134ffa1d8e23bc0daadf4d109c864d43b2cf0898e4c122;

        bytes32 validatorTreeRoot;
        bytes32 validatorRoot;

        if(validatorIndex == 0){
  
            validatorContainerFields.push(0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f);
            validatorContainerFields.push(0x01000000000000000000000093939caed8a5a52e4dda47b64579ce1a5c8549dc);
            validatorContainerFields.push(0x0040597307000000000000000000000000000000000000000000000000000000);
            validatorContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
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
            validatorTreeRoot = 0x1c876fb5791efb82972ef936d1439d4822cb8ee453527d390ee018db1431ac16;
            
            //hash tree root of individual validator container
            validatorRoot = 0xa99e7a64a6bc9bedbf201d4c857f561066a4439387f72db22cfb1ec27cc09d4b;
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
            
            validatorMerkleProof[0] = 0xa99e7a64a6bc9bedbf201d4c857f561066a4439387f72db22cfb1ec27cc09d4b;
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
            validatorTreeRoot = 0x1c876fb5791efb82972ef936d1439d4822cb8ee453527d390ee018db1431ac16;
            
            //hash tree root of individual validator container
            validatorRoot = 0xfe3f978f8be10d5713f3548ee71dfbacabb0763433fea9080b7e71e87bd9cd5b;

        }

        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);

    }
    //simulates a 16ETH slashing
    function getSlashedDepositProof(uint40 validatorIndex) public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){

        
        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a7c6aed738e0a0cf25ebb8c5b4da41173285b41451674890a0ca5a100c2d3c9;
        beaconStateMerkleProofForValidators[2] = 0xd63afe2579fd495c87de3b1dc9dded10c6e65b1a717a4efed9e826b969e2a6d9;
        beaconStateMerkleProofForValidators[3] = 0x086ef90e3db0073ad2f8b2e6b38653d726e850fde26859dd881da1ac523598f0;
        beaconStateMerkleProofForValidators[4] = 0x1260718cd540a187a9dcff9f4d39116cdc1a0aed8a94fbe7a69fb87eae747be5;

        beaconStateRoot = 0x929255f32dc83d1d6ca96afc5085af53edd469b8812b3ff247f4bb2b08977d05;

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

    //proofs for a podOwner that's a contract (only difference between this and getInitialDepositProof is that the validatorContainerFields[1]
    // is a different withdrawal credential)
    function getContractAddressWithdrawalCred() public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){
        
        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a7c6aed738e0a0cf25ebb8c5b4da41173285b41451674890a0ca5a100c2d3c9;
        beaconStateMerkleProofForValidators[2] = 0xd63afe2579fd495c87de3b1dc9dded10c6e65b1a717a4efed9e826b969e2a6d9;
        beaconStateMerkleProofForValidators[3] = 0x086ef90e3db0073ad2f8b2e6b38653d726e850fde26859dd881da1ac523598f0;
        beaconStateMerkleProofForValidators[4] = 0x1260718cd540a187a9dcff9f4d39116cdc1a0aed8a94fbe7a69fb87eae747be5;

        beaconStateRoot = 0x5dc761d793641799e9f23fb1d9836fc9b8d18dde6899dbcc551901e67da4c964;
  
  
        validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
        validatorContainerFields[1] = 0x01000000000000000000000065481165de5cefa4c432a0835b313af4c0d70988;
        validatorContainerFields[2] = 0x0040597307000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[3] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[4] = 0x0200000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[5] = 0x0300000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
        
        
        
        validatorMerkleProof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
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
        validatorMerkleProof[40] = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        
        //hash tree root of list of validators
        bytes32 validatorTreeRoot = 0x16f93d0a10472f29fd5d86b9c4584de6ccaa0a8f20b59c65efed8ea939b51598;
        
        //hash tree root of individual validator container
        bytes32 validatorRoot = 0x82e7d4762ba43701fa3f4b35f8f459a702b50bd2cad66354d28326972b2f0a39;

        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);
    }


    function getCompleteWithdrawalProof() public returns(bytes32, bytes32[5] memory, bytes32[] memory, bytes32[] memory, bytes32, bytes32){
        
        beaconStateMerkleProofForValidators[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        beaconStateMerkleProofForValidators[1] = 0x8a7c6aed738e0a0cf25ebb8c5b4da41173285b41451674890a0ca5a100c2d3c9;
        beaconStateMerkleProofForValidators[2] = 0xd63afe2579fd495c87de3b1dc9dded10c6e65b1a717a4efed9e826b969e2a6d9;
        beaconStateMerkleProofForValidators[3] = 0x086ef90e3db0073ad2f8b2e6b38653d726e850fde26859dd881da1ac523598f0;
        beaconStateMerkleProofForValidators[4] = 0x1260718cd540a187a9dcff9f4d39116cdc1a0aed8a94fbe7a69fb87eae747be5;

        beaconStateRoot = 0xf3a1a6b828fb140ae6b1dc391e04b86b74d9a5e19ae44a5499b85dac20d65daa;
  
  
        validatorContainerFields[0] = 0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f;
        validatorContainerFields[1] = 0x01000000000000000000000065481165de5cefa4c432a0835b313af4c0d70988;
        validatorContainerFields[2] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[3] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[4] = 0x0200000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[5] = 0x0300000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[6] = 0x0600000000000000000000000000000000000000000000000000000000000000;
        validatorContainerFields[7] = 0x0900000000000000000000000000000000000000000000000000000000000000;
        
        
        
        validatorMerkleProof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
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
        validatorMerkleProof[40] = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        
        //hash tree root of list of validators
        bytes32 validatorTreeRoot = 0x66777158de01d047e5abeecd6ebc8d88f8c89398b37aa755f9447d78beaca435;
        
        //hash tree root of individual validator container
        bytes32 validatorRoot = 0x3be5fde83992387d237105f4df6553dd09af62141107ccaa820ccacb9cd0b800;

        return (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot);
    }

    function getWithdrawalProof() public returns(bytes32[] memory, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory){
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0040597307000000000000000000000000000000000000000000000000000000);
        
        beaconStateRoot = 0x6e9e0b08cf3d701d6d1a32576605b608432f99ad9925dc014a145b3374438900;
        
        beaconStateMerkleProofForExecutionPayloadHeader.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        beaconStateMerkleProofForExecutionPayloadHeader.push(0x8a023a9e4affbb255a6b48ae85cc4a7d1a1b9e8e6809fe9e48535c01c1fc071a);
        beaconStateMerkleProofForExecutionPayloadHeader.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        beaconStateMerkleProofForExecutionPayloadHeader.push(0x2e9e44d45a41f0e0da340441f66894d25a002b0e18361bc156963eab8a62c597);
        beaconStateMerkleProofForExecutionPayloadHeader.push(0x5d1b41cdba61e9cebf2a8a3fbf2970360145f711dd0832bfbef1cd72ecd4e8b1);
        
        executionPayloadHeaderRoot = 0x2d4c1a5bf7892ee5755be6552e5bdde6fc19c43aee7afe42f3c5984e0b6d9d3b;
        
        executionPayloadHeaderProofForWithdrawalProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProofForWithdrawalProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        executionPayloadHeaderProofForWithdrawalProof.push(0x7e716846ef6aade1cdc8586ab65a207f2e94e03bbdcd320da73f2307e872a0fb);
        executionPayloadHeaderProofForWithdrawalProof.push(0x83ff25f2887e963d4d555834b7a0a9db85633d8d8f095e645d14d652d26aabb3);
        
        
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        withdrawalMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        withdrawalMerkleProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
 

        
        return (
            withdrawalContainerFields, 
            beaconStateRoot, 
            beaconStateMerkleProofForExecutionPayloadHeader, 
            executionPayloadHeaderProofForWithdrawalProof, 
            withdrawalMerkleProof
        );
    }

    function getHistoricalBeaconStateProof() public returns(bytes32, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory, bytes32[] memory){

        beaconStateRoot = 0x6e9e0b08cf3d701d6d1a32576605b608432f99ad9925dc014a145b3374438900;
        executionPayloadHeaderRoot = 0x2d4c1a5bf7892ee5755be6552e5bdde6fc19c43aee7afe42f3c5984e0b6d9d3b;
  
        beaconStateMerkleProofForHistoricalRoots.push(0x75f5119e1076308e7af941d986f8f43f77229bc584dfb317b3684b9effd31748);
        beaconStateMerkleProofForHistoricalRoots.push(0x117339c4650c5876ca49006e4b7cf84ae2d458b1d2dfdeda7955662f218986fb);
        beaconStateMerkleProofForHistoricalRoots.push(0xd803e35a1072c0bfd4562ca0e2f669f9c0fea5e0e26bfbd82efcb57ac757f501);
        beaconStateMerkleProofForHistoricalRoots.push(0x3ebc4827204cc607c86f8d877027ce611149c1cf63715269bad269751bcdaf78);
        beaconStateMerkleProofForHistoricalRoots.push(0xfdd6a5ae64e3a7372d3894b854acb02c7a2cfe17d4b7e80c4a34c60295540e7e);
                
        historicalRootsMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        historicalRootsMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        historicalRootsMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        historicalRootsMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        historicalRootsMerkleProof.push(0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c);
        historicalRootsMerkleProof.push(0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30);
        historicalRootsMerkleProof.push(0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1);
        historicalRootsMerkleProof.push(0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c);
        historicalRootsMerkleProof.push(0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193);
        historicalRootsMerkleProof.push(0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1);
        historicalRootsMerkleProof.push(0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b);
        historicalRootsMerkleProof.push(0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220);
        historicalRootsMerkleProof.push(0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f);
        historicalRootsMerkleProof.push(0xdf6af5f5bbdb6be9ef8aa618e4bf8073960867171e29676f8b284dea6a08a85e);
        historicalRootsMerkleProof.push(0xb58d900f5e182e3c50ef74969ea16c7726c549757cc23523c369587da7293784);
        historicalRootsMerkleProof.push(0xd49a7502ffcfb0340b1d7885688500ca308161a7f96b62df9d083b71fcc8f2bb);
        historicalRootsMerkleProof.push(0x8fe6b1689256c0d385f42f5bbe2027a22c1996e110ba97c171d3e5948de92beb);
        historicalRootsMerkleProof.push(0x8d0d63c39ebade8509e0ae3c9c3876fb5fa112be18f905ecacfecb92057603ab);
        historicalRootsMerkleProof.push(0x95eec8b2e541cad4e91de38385f2e046619f54496c2382cb6cacd5b98c26f5a4);
        historicalRootsMerkleProof.push(0xf893e908917775b62bff23294dbbe3a1cd8e6cc1c35b4801887b646a6f81f17f);
        historicalRootsMerkleProof.push(0xcddba7b592e3133393c16194fac7431abf2f5485ed711db282183c819e08ebaa);
        historicalRootsMerkleProof.push(0x8a8d7fe3af8caa085a7639a832001457dfb9128a8061142ad0335629ff23ff9c);
        historicalRootsMerkleProof.push(0xfeb3c337d7a51a6fbf00b9e34c52e1c9195c969bd4e7a0bfd51d5c5bed9c1167);
        historicalRootsMerkleProof.push(0xe71f0aa83cc32edfbefa9f4d3e0174ca85182eec9f3a09f6a6c0df6377a510d7);
        historicalRootsMerkleProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        
        
        historicalBatchMerkleProof.push(0xcc526c67100d6a2d0337b393c442da2be638390df7316b5187889f3d6607e401);
        
        
        stateRootsMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        stateRootsMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        stateRootsMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        stateRootsMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        stateRootsMerkleProof.push(0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c);
        stateRootsMerkleProof.push(0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30);
        stateRootsMerkleProof.push(0xd88ddfeed400a8755596b21942c1497e114c302e6118290f91e6772976041fa1);
        stateRootsMerkleProof.push(0x87eb0ddba57e35f6d286673802a4af5975e22506c7cf4c64bb6be5ee11527f2c);
        stateRootsMerkleProof.push(0x26846476fd5fc54a5d43385167c95144f2643f533cc85bb9d16b782f8d7db193);
        stateRootsMerkleProof.push(0x506d86582d252405b840018792cad2bf1259f1ef5aa5f887e13cb2f0094f51e1);
        stateRootsMerkleProof.push(0xffff0ad7e659772f9534c195c815efc4014ef1e1daed4404c06385d11192e92b);
        stateRootsMerkleProof.push(0x6cf04127db05441cd833107a52be852868890e4317e6a02ab47683aa75964220);
        stateRootsMerkleProof.push(0xb7d05f875f140027ef5118a2247bbb84ce8f2f0f1123623085daf7960c329f5f);

        return(
            beaconStateRoot,
            historicalRootToVerify,
            beaconStateMerkleProofForHistoricalRoots, 
            historicalRootsMerkleProof,
            historicalBatchMerkleProof,
            stateRootsMerkleProof
        );
    }

    function getWithdrawalProofsWithBlockNumber() public returns(bytes32, bytes32, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory, bytes32[] memory) {

       withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x00fa954f07000000000000000000000000000000000000000000000000000000);
        
        beaconStateRoot = 0x4d3f65f6cfc68e5d9aba72e0f6147a582b307d4d584eb33d959459d81f3d1e8f;
        blockNumberRoot = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        executionPayloadHeaderRoot = 0x53d8695c5c656722bc66f45fe207ffce1f86d93872c3cef7dd314bd84cdf0abb;
        
        executionPayloadHeaderProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0x8a023a9e4affbb255a6b48ae85cc4a7d1a1b9e8e6809fe9e48535c01c1fc071a);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0x2e9e44d45a41f0e0da340441f66894d25a002b0e18361bc156963eab8a62c597);
        executionPayloadHeaderProof.push(0x4520eb0bc3182ca3b0f742e524276cc7f5ea7b80376f6181df89cb7925fb531f);
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
        executionPayloadHeaderProof.push(0x93a2ef70ed571c21aeeb45692e55057c4b863010f75a38041422ac444d790f1b);
        executionPayloadHeaderProof.push(0x5a374976a34347c1b56054efcf4f2029c6ec8d34b55385d608475a533a2cce37);
        executionPayloadHeaderProof.push(0x3ebc4827204cc607c86f8d877027ce611149c1cf63715269bad269751bcdaf78);
        executionPayloadHeaderProof.push(0xc9db8a9e805548dbb30b9c8ee23110e9685fd295072751b4567fdba4d6bed5b3);
        
        blockNumberProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        blockNumberProof.push(0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6);
        blockNumberProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        blockNumberProof.push(0xea5587900c21565b4a4bdfc9dcbf8dfdc4960a8d16e8d046d76c3462c946babf);
        
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        withdrawalMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        withdrawalMerkleProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0x7e716846ef6aade1cdc8586ab65a207f2e94e03bbdcd320da73f2307e872a0fb);
        withdrawalMerkleProof.push(0x83ff25f2887e963d4d555834b7a0a9db85633d8d8f095e645d14d652d26aabb3);


        return(beaconStateRoot, executionPayloadHeaderRoot, blockNumberRoot, executionPayloadHeaderProof, blockNumberProof, withdrawalMerkleProof, withdrawalContainerFields);
    }

    function getInsufficientFullWithdrawalProof() public returns(bytes32, bytes32, bytes32, bytes32[] memory, bytes32[] memory, bytes32[] memory, bytes32[] memory) {
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalContainerFields.push(0x00ca9a3b00000000000000000000000000000000000000000000000000000000);
        
        beaconStateRoot = 0xe96752d404431c4db179cddfa820151937a0f5d1be80aef3755b7b12f5d25cb4;
        blockNumberRoot = 0x0100000000000000000000000000000000000000000000000000000000000000;
        
        executionPayloadHeaderRoot = 0xd1242a717362658cef6b5ef0b32e2a5bd2d2081d576ff831164f2e5e00a60940;
        
        executionPayloadHeaderProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        executionPayloadHeaderProof.push(0x8a023a9e4affbb255a6b48ae85cc4a7d1a1b9e8e6809fe9e48535c01c1fc071a);
        executionPayloadHeaderProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        executionPayloadHeaderProof.push(0x2e9e44d45a41f0e0da340441f66894d25a002b0e18361bc156963eab8a62c597);
        executionPayloadHeaderProof.push(0x4520eb0bc3182ca3b0f742e524276cc7f5ea7b80376f6181df89cb7925fb531f);
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
        executionPayloadHeaderProof.push(0xbf468bb123590a610b7bbf2738bcefea99fdbcae94015a4e036fd187a3151372);
        executionPayloadHeaderProof.push(0x5a374976a34347c1b56054efcf4f2029c6ec8d34b55385d608475a533a2cce37);
        executionPayloadHeaderProof.push(0x3ebc4827204cc607c86f8d877027ce611149c1cf63715269bad269751bcdaf78);
        executionPayloadHeaderProof.push(0x91ef6a0f6f33fc137d6c73ec8950274a2593115552d10aad9cdbde9b4e9dd5ac);
        
        blockNumberProof.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        blockNumberProof.push(0xe8e527e84f666163a90ef900e013f56b0a4d020148b2224057b719f351b003a6);
        blockNumberProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        blockNumberProof.push(0x31ab016430e7310b299a435167486abad476fc9675477fc66189b07ab1451973);
        
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71);
        withdrawalMerkleProof.push(0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c);
        withdrawalMerkleProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        withdrawalMerkleProof.push(0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b);
        withdrawalMerkleProof.push(0x7e716846ef6aade1cdc8586ab65a207f2e94e03bbdcd320da73f2307e872a0fb);
        withdrawalMerkleProof.push(0x83ff25f2887e963d4d555834b7a0a9db85633d8d8f095e645d14d652d26aabb3);
        return(beaconStateRoot, executionPayloadHeaderRoot, blockNumberRoot, executionPayloadHeaderProof, blockNumberProof, withdrawalMerkleProof, withdrawalContainerFields);
    }
}