// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mocks/DisclosureChallenge.sol";

import "forge-std/Test.sol";
import "./mocks/Multiplication.sol";

contract DisclosureDeployer is DSTest {
    Vm cheats = Vm(HEVM_ADDRESS);
    DataLayrDisclosureChallenge public dc;

    address challenger = address(0x1111128043334532291375821752135089127385);
    address operator = address(0x9999928043334532291375821752135089127385);

    function setUp() public {
        dc = new DataLayrDisclosureChallenge(
            operator,
            challenger,
            7854113937738702622800385629703466717680574548389714659870857137267464804073,
            18928487978255974683182365919351708004921580380066122372704872217133715132259,
            11473828264278755767020150732487994496068087961463510690446977072347609057769,
            8052269009961205989060174082418769849059449545073451984290983643162314163903,
            2
        );
    }

    function testCommitToSamePolynomial() public {
        cheats.prank(operator);
        uint256[4] memory coors;
        coors[
            0
        ] = 14454340801642512897465483173279507241180053951973046131536861267080193565607;
        coors[
            1
        ] = 7300128489156653597012057502047524010933616474553200909590131210838584218171;
        coors[
            2
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            3
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        cheats.expectRevert("Cannot commit to same polynomial as DLN");
        dc.challengeCommitmentHalf(true, coors);
    }

    function testChallengerCannotRespondNotOnTheirTurn() public {
        cheats.prank(challenger);
        uint256[4] memory coors;
        coors[
            0
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            1
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        coors[
            2
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            3
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        cheats.expectRevert(
            "Must be challenger and thier turn or operator and their turn"
        );
        dc.challengeCommitmentHalf(true, coors);
    }

    function testOperatorCannotRespondAfterInterval() public {
        cheats.prank(operator);
        cheats.warp(block.timestamp + 7 days);
        uint256[4] memory coors;
        coors[
            0
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            1
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        coors[
            2
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            3
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        cheats.expectRevert("Fraud proof interval has passed");
        dc.challengeCommitmentHalf(true, coors);
    }

    function testCannotDoDissectionWhenSupposedToOneStep() public {
        //respond
        cheats.prank(operator);
        uint256[4] memory coors;
        coors[
            0
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            1
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        coors[
            2
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            3
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        dc.challengeCommitmentHalf(true, coors);
        //respond back
        cheats.prank(challenger);
        coors[
            0
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            1
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        coors[
            2
        ] = 1598068943238092412304148656922757962511866396290769884304254861045104315194;
        coors[
            3
        ] = 2840856310821858817649113726190482393961047895798363457470935309452021117098;
        cheats.expectRevert("Time to do one step proof");
        dc.challengeCommitmentHalf(true, coors);
    }

    function testCannotDoOneStepWhenNotTurn() public {
        //respond
        cheats.prank(operator);
        uint256[4] memory coors;
        coors[
            0
        ] = 12623042442131138433218131872348034718530098703302257680506121880219970513239;
        coors[
            1
        ] = 17063130108049825168764659754731928816245619340444518567222000281866131469355;
        coors[
            2
        ] = 16021416397311877923351017713527508996348613744360009971459449207531314478848;
        coors[
            3
        ] = 5867550432962507573704372579384352852364626287621156286726787059052804067882;
        dc.challengeCommitmentHalf(true, coors);
        //respond back
        cheats.prank(challenger);
        bool[] memory flags = new bool[](2);
        flags[0] = true;
        flags[1] = true;
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 
                bytes32(
                    0x18c5e5d9db855fc2bfa2ff4fa8bc1f01e813dbfc3c698573a800f230a2554e89
                );
        proof[1] = 
                bytes32(
                    0x9cd261b77934b80c8e1b2bbb85740d440751bed87f429e629a8c57cc84591994
                );
        bytes memory poly = new bytes(32);
        for (uint i = 0; i < poly.length - 1; i++) {
            poly[i] = 0;
        }
        poly[poly.length - 1] = 0xFF;
        dc.respondToDisclosureChallengeFinal(
            true,
            bytes32(0),
            1,
            2,
            poly,
            flags,
            proof
        );
    }

    function testMultiply() public {
        Multiplication mul = new Multiplication();
        mul.multiply();
    }
}
