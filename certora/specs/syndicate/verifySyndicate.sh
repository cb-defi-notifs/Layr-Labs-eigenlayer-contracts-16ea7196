if [[ "$1" ]]
then
    RULE="--rule $1"
fi

solc-select use 0.8.13

certoraRun  certora/harnesses/SyndicateHarness.sol \
    certora/munged/banking/sETH.sol \
    --verify SyndicateHarness:certora/specs/syndicate/Syndicate.spec \
    --staging \
    --optimistic_loop \
    --send_only \
    --optimize 1 \
    --loop_iter 1 \
    $RULE \
    --rule_sanity \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin \
    --msg "Syndicate $1 $2"

    # certora/harnesses/MockStakeHouseUniverse.sol \
    # certora/harnesses/MockStakeHouseRegistry.sol \
    # certora/munged/banking/SlotSettlementRegistry.sol \

# --settings -smt

#     --settings -smt_hashingScheme=PlainInjectivity \
#PlainInjectivity, Legacy,