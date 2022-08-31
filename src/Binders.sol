// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Owned} from "solmate/auth/Owned.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol";

abstract contract ERC1155TokenReceiver {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}

interface IERC20 {
    function balanceOf(address) external returns(uint256);
    function transfer(address, uint256) external returns (bool);
}

interface IERC1155 {
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external; 

    function setApprovalForAll(address, bool) external;
}

interface IPrimeRewards {
    function endTimestamp() external returns(uint256);
    function getPoolTokenIds(uint256) external returns(uint256[] memory);
    function cache(uint256, uint256) external;
    function withdraw(uint256, uint256) external;
    function claimPrime(uint256) external;
    function parallelAlpha() external returns(address);
    function PRIME() external returns(address);
}

interface ISplitMain {
  function createSplit(
    address[] calldata accounts,
    uint32[] calldata percentAllocations,
    uint32 distributorFee,
    address controller
  ) external returns (address);
}

interface IPrimeEvent {
    function claim(
        uint256,
        uint256,
        uint256,
        bytes32[] calldata
    ) external;
}

interface IFactory {
    function locked() external view returns(bool);
    function cardsToPercent(uint256) external view returns(uint256);
}

contract Binder is ERC1155TokenReceiver {
    // Add the library methods
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    event Deposit(address indexed user, uint256 cardId);
    event Withdraw(address indexed user, uint256 cardId);
    event Cached();
    event OwnerUpdated(address indexed user, address indexed newOwner);

    // 0xECa9D81a4dC7119A40481CFF4e7E24DD0aaF56bD
    IPrimeRewards public CACHING;
    // 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE
    ISplitMain public SPLITS;
    IFactory public FACTORY;
    uint256[] public cards;
    bool public initialized;

    address public owner;

    address public split;
    uint256 public pid;
    uint256 public totalCardsNeeded = 0;
    uint256 public totalCardsDeposited = 0;
    
    enum Stages{Setup, Cached, Finished}
    Stages public stage;

    // The cards in the set
    mapping(uint256 => bool) public cardInSet;
    // The owners of cards in the set
    mapping(uint256 => address) public cardToOwner;
    // Declare a set state variable
    EnumerableMap.AddressToUintMap private addressToPercent;

    constructor(address _rewards) {
        init(address(0), address(0), _rewards, address(0), 0, cards);
    }

    function init(address _factory, address _owner, address _rewards, address _splits, uint256 _pid, uint256[] memory _cards) public {
        require(!initialized, "INITIALIZED");
        initialized = true;
        owner = _owner;
        CACHING = IPrimeRewards(_rewards);
        SPLITS = ISplitMain(_splits);
        FACTORY = IFactory(_factory);
        pid = _pid;
        cards = _cards;
        totalCardsNeeded = cards.length;
        // add the cards to the set
        for (uint256 x = 0; x < cards.length; x++) {
            cardInSet[cards[x]] = true;
        }

        IERC1155(CACHING.parallelAlpha()).setApprovalForAll(address(CACHING), true);
    }

    modifier isSetup() {
        require(stage == Stages.Setup, "not setup");
        _;
    }

    modifier isCached() {
        require(stage == Stages.Cached, "not cached");
        _;
    }

    function getAddressPercent(address user) public view returns(uint256) {
        return addressToPercent.get(user);
    }

    function _deposit(address user, uint256 cardId) internal isSetup {
        require(cardToOwner[cardId] == address(0), "already deposited");
        require(cardInSet[cardId], "not in set");
        cardToOwner[cardId] = user;
        totalCardsDeposited++;

        emit Deposit(user, cardId);
    }

    /// @notice Withdraw a card from the set. Requires we are not locked.
    /// @param cardId The id of the card we want to withdraw.
    function withdraw(uint256 cardId) public {
        IERC1155(CACHING.parallelAlpha()).safeTransferFrom(address(this), msg.sender, cardId, 1, "0x0");
        _withdraw(cardId);
    }

    /// @notice Withdraw multiple cards from the set. Requires we are not locked.
    /// @param cardIds The ids of the cards we want to withdraw.
    function batchWithdraw(uint256[] calldata cardIds) public {
        uint256[] memory amounts = new uint256[](cardIds.length);
        for (uint256 x = 0; x < cardIds.length; x++) {
            amounts[x] = 1;
        }

        IERC1155(CACHING.parallelAlpha()).safeBatchTransferFrom(address(this), msg.sender, cardIds, amounts, "0x0");
        for (uint256 x = 0; x < cardIds.length; x++) {
            _withdraw(cardIds[x]);
        }
    }

    function _withdraw(uint256 cardId) internal {
        require(stage != Stages.Cached, "you're cached");
        require(cardToOwner[cardId] == msg.sender, "not owner");
        cardToOwner[cardId] = address(0);
        totalCardsDeposited--;
  
        emit Withdraw(msg.sender, cardId);
    }

    /// @notice Attempt to cache. Will only work if we have all the cards needed.
    function cache() external {   
        require(totalCardsDeposited == totalCardsNeeded, "not full");

        uint256 percentTotal = 0;
        // we have to loop through all cards to generate an address list with their % of rewards
        for (uint256 i = 0; i < cards.length; i++) {
            uint256 percentOfPrime = FACTORY.cardsToPercent(cards[i]);
            address cardOwner = cardToOwner[cards[i]];
            percentTotal += percentOfPrime;
            (, uint256 total) = addressToPercent.tryGet(cardOwner);
            addressToPercent.set(cardOwner, total + percentOfPrime);
        }

        address[] memory accounts = new address[](addressToPercent.length() + 1);
        uint32[] memory percentAllocations = new uint32[](addressToPercent.length() + 1);
        for (uint256 x = 0; x < addressToPercent.length(); x++) {
            (address tempAddr,uint256 percent) = addressToPercent.at(x);
            accounts[x] = tempAddr;
        }
        accounts[addressToPercent.length()] = owner;
        addressToPercent.set(owner, 1000000 - percentTotal);

        // now we have a sorted account list
        // lets loop through and set the percents now
        accounts = sortAddresses(accounts);

        // now lets make a percents array with the sorted array
        for (uint256 y = 0; y < accounts.length; y++) {
            percentAllocations[y] = uint32(addressToPercent.get(accounts[y]));
        }

        split = SPLITS.createSplit(accounts, percentAllocations, 0, address(0));
        CACHING.cache(pid, 1);
        stage = Stages.Cached;

        emit Cached();
    }

    /// @notice Uncache all NFTs
    function uncache() public isCached {
        _finish();
        CACHING.withdraw(pid, 1);
    }

    /// @notice Unlock the vault. Can be one in three ways. By owner, staking ends, 1 year.
    function _finish() internal {
        if (!FACTORY.locked()) {
            stage = Stages.Finished;
        } else if (block.timestamp > CACHING.endTimestamp()) {
            stage = Stages.Finished;
        } else if (block.timestamp > 1689938234) {
            stage = Stages.Finished;
        } else {
            revert();
        }
    }

    /// @notice Claim all available PRIME rewards.
    function claimPrime() public {
        CACHING.claimPrime(pid);
    }

    /// @notice Will send Prime to split contract
    function splitPrime() public {
        IERC20(CACHING.PRIME()).transfer(split, IERC20(CACHING.PRIME()).balanceOf(address(this)));
    }

    /// @notice Claim a prime event
    function claimPrimeEvent(address claimAddress, uint256 claimAmount, uint256 index, uint256 maximumAmount, bytes32[] calldata merkleProof) public {
        IPrimeEvent(claimAddress).claim(claimAmount, index, maximumAmount, merkleProof);
    }

    function sortAddresses (address [] memory addresses) internal pure returns (address [] memory) {
        for (uint256 i = addresses.length - 1; i > 0; i--)
            for (uint256 j = 0; j < i; j++)
                if (addresses [i] < addresses [j])
                    (addresses [i], addresses [j]) = (addresses [j], addresses [i]);

        return addresses;
    }

    /// @notice Handles the receipt of a single ERC1155 token type
    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 amount,
        bytes calldata
    ) external virtual override returns (bytes4) {
        require(amount == 1, "can only be 1");
        if (from != address(CACHING))
            _deposit(from, id);
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata
    ) external virtual override returns (bytes4) {
        for (uint256 x = 0; x < ids.length; x++) {
            require(amounts[x] == 1, "can only be 1");
            if (from != address(CACHING))
                _deposit(from, ids[x]);
        }
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}

/*
The MIT License (MIT)

Copyright (c) 2018 Murray Software, LLC.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
//solhint-disable max-line-length
//solhint-disable no-inline-assembly

contract CloneFactory {

  function createClone(address target) internal returns (address result) {
    bytes20 targetBytes = bytes20(target);
    assembly {
      let clone := mload(0x40)
      mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
      mstore(add(clone, 0x14), targetBytes)
      mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
      result := create(0, clone, 0x37)
    }
  }

  function isClone(address target, address query) internal view returns (bool result) {
    bytes20 targetBytes = bytes20(target);
    assembly {
      let clone := mload(0x40)
      mstore(clone, 0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000)
      mstore(add(clone, 0xa), targetBytes)
      mstore(add(clone, 0x1e), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)

      let other := add(clone, 0x40)
      extcodecopy(query, other, 0, 0x2d)
      result := and(
        eq(mload(clone), mload(other)),
        eq(mload(add(clone, 0xd)), mload(add(other, 0xd)))
      )
    }
  }
}

contract Factory is Owned, CloneFactory {

    event NewBinder(uint256 pid, address addr);

    address public rewards;
    address public splits;
    address public implementation;
    bool public locked;

    mapping(uint256 => uint256) public cardsToPercent;

    constructor(address _rewards, address _splits) Owned(msg.sender) {
        rewards = _rewards;
        splits = _splits;
        locked = true;
        implementation = address(new Binder(rewards));
    }

    function updateCardsToPercent(uint256[] calldata _cards, uint256[] calldata _percents) public onlyOwner {
        require(_cards.length == _percents.length, "mismatch");
        for (uint256 x = 0; x < _cards.length; x++) {
            cardsToPercent[_cards[x]] = _percents[x];
        }
    }

    function newBinder(uint256 pid) public returns(address){
        uint256[] memory ids = IPrimeRewards(rewards).getPoolTokenIds(pid);
        address binder = createClone(implementation);
        Binder(binder).init(address(this), owner, rewards, splits, pid, ids);
        emit NewBinder(pid, address(binder));
        return binder;
    }

    function unlock() external onlyOwner {
        locked = false;
    }
}

contract FactoryDeployerHelper is Owned {

    address public rewards;
    address public splits;

    uint256[] public PD2FEcards = [10371,10372,10445,10350,10388,10346,10446,10307,10391,10320,10324,10309,10395,10356,10363,10365];
    uint256[] public PD2FEprcnt = [2695,2695,82423,21230,21894,24158,24158,25021,21894,21894,87574,87574,87574,77844,180687,180687];

    uint256[] public PD3FEcards = [10523,10512,10545,10531,10506,10508,10517,10539,10547,10558,10560,10562,10568,10572,10617,10566,10494,10500,10502,10510,10514,10516,10550,10521,10525,10527,10529,10537,10533,10504,10543,10519,10556,10564,10570,10615,10535,10541,10498,10552,10553];
    uint256[] public PD3FEpcnts = [6045,1008,1008,17272,60451,17272,17272,6045,60451,17272,6045,6045,17272,17272,17272,1008,6045,1008,17272,1008,17272,60451,6045,1008,6045,6045,1008,17272,17272,6045,1008,1008,1008,6045,1008,1008,1008,6045,1008,236524,236524];

    uint256[] public PD1FEcards = [10175,10268,10150,10210,10235,10153,10133,10259,10275,10181,10262,10258,10240,10178,10114,10241,10119,10187,10111,10265,10207,10172,10246,10247];
    uint256[] public PD1FEpcnts = [16337,16337,16337,12101,16337,16337,10540,32674,16337,21783,16337,32674,32674,16337,10891,32674,46677,40842,65348,40842,16337,21783,188232,188232];

    uint256[] public PD1ARTcards = [10214,10215,10216,10217,10218,10219,10220,10221,10222,10223];
    uint256[] public PD1ARTpcnts = [92500,92500,92500,92500,92500,92500,92500,92500,92500,92500];

    uint256[] public PD1CBcards = [10224,10226,10227,10228,10229];
    uint256[] public PD1CBpcnts = [185000,185000,185000,185000,185000];

    uint256[] public PD1SEcards = [10296,10288,10263,10161,10140,10137,10134,10154,10208,10279,10236,10106,10109,10159,10126,10112,10206,10295,10176,10152,10156,10142,10185,10276,10245,10144,10290,10115,10151,10244,10255,10297,10252,10289,10286,10287,10256,10173,10170,10179,10260,10285,10284,10238,10182,10291,10189,10120,10266,10239,10248,10249];
    uint256[] public PD1SEpcnts = [4179,8358,12538,6269,4179,6269,12538,12538,4179,4179,12538,6269,4179,6269,12538,25075,12538,4179,12538,6269,6269,4179,4179,12538,12538,6269,12538,12538,12538,12538,12538,12538,12538,8358,8358,8358,12538,12538,6269,12538,25075,25075,12538,25075,12538,12538,25075,25075,25075,25075,165774,165774];

    uint256[] public PD2ARTcards = [10448,10449,10450,10451,10452,10453,10454,10455];
    uint256[] public PD2ARTpcnts = [115625,115625,115625,115625,115625,115625,115625,115625];

    uint256[] public PD2CBcards = [10476,10477,10478,10479,10480];
    uint256[] public PD2CBpcnts = [185000,185000,185000,185000,185000];

    uint256[] public PD2PLcards = [10465,10292,10466,10467,10469,10293,10294];
    uint256[] public PD2PLpcnts = [46250,46250,46250,92500,92500,300625,300625];

    uint256[] public PD2SEcards = [10317,10323,10355,10312,10331,10396,10368,10385,10398,10327,10374,10319,10392,10362,10447,10339,10333,10335,10341,10337,10394,10345,10379,10343,10349,10444,10329,10483,10351,10370,10315,10360,10375,10325,10347,10308,10389,10357,10310,10321,10366,10364];
    uint256[] public PD2SEpcnts = [6033,6033,6033,6033,6033,36196,12065,9049,6033,9049,12065,9049,18098,12065,18098,9049,9049,9049,6033,6033,9049,6033,9049,6033,9049,36196,9049,9049,18098,12065,9049,12065,12065,36196,18098,18098,18098,36196,36196,18098,188013,188013];

    uint256[] public PD3ARTcards = [10636,10637,10638,10640,10641,10642,10643,10644];
    uint256[] public PD3ARTpcnts = [115625,115625,115625,115625,115625,115625,115625,115625];

    uint256[] public PD3CBcards = [10630,10631,10632,10633,10635];
    uint256[] public PD3CBpcnts = [185000,185000,185000,185000,185000];

    uint256[] public PD3PLcards = [10627,10645,10625,10490,10628,10629];
    uint256[] public PD3PLpcnts = [18750,56250,56250,112500,340625,340625];

    uint256[] public PD3SEcards = [10499,10528,10520,10524,10565,10546,10526,10571,10569,10573,10513,10501,10518,10511,10618,10522,10538,10616,10549,10505,10567,10536,10532,10542,10530,10557,10507,10515,10534,10544,10540,10509,10563,10561,10495,10503,10551,10491,10559,10555,10554];
    uint256[] public PD3SEpcnts = [6576,9864,6576,9864,9864,6576,9864,6576,19727,19727,6576,6576,19727,6576,19727,6576,19727,6576,39455,9864,6576,6576,19727,9864,6576,6576,39455,19727,19727,6576,9864,19727,9864,9864,9864,19727,9864,39455,19727,194535,194535];

    uint256[] public PS15FEcards = [16,20,15,17,12,10,9,13,8,18,14,19,11];
    uint256[] public PS15FEpcnts = [26638,39957,7991,3996,26638,88794,7991,7991,2664,1598,236914,236914,236914];

    uint256[] public PS15ARTcards = [27,28,29,30,31,33,34,35];
    uint256[] public PS15ARTpcnts = [115625,115625,115625,115625,115625,115625,115625,115625];

    uint256[] public PS15CBcards = [36,37,38,39,40];
    uint256[] public PS15CBpcnts = [185000,185000,185000,185000,185000];

    uint256[] public PS15SEcards = [69,64,86,70,66,74,88,67,65,73,72,76,68];
    uint256[] public PS15SEpcnts = [41509,50075,40970,50075,70105,33207,59523,50075,43215,19354,67121,199886,199886];

    uint256[] public PD4ARTcards = [10685,10693,10701,10704,10708,10728,10731,10745,10748,10772];
    uint256[] public PD4ARTpcnts = [92500,92500,92500,92500,92500,92500,92500,92500,92500,92500];

    uint256[] public PD4CBcards = [10666,10688,10705,10726,10746];
    uint256[] public PD4CBpcnts = [185000,185000,185000,185000,185000];

    uint256[] public PD4FEcards = [10653,10679,10721,10655,10715,10739,10717,10719,10675,10677,10769,10765,10767,10741,10681];
    uint256[] public PD4FEpcnts = [25227,25227,25227,25227,25227,25227,25227,25227,25227,25227,134546,134546,134546,134546,134546];

    uint256[] public PD4SEcards = [10752,10710,10734,10672,10660,10712,10764,10754,10674,10736,10658,10699,10756,10652,10697,10662,10714,10740,10695,10654,10758,10762,10676,10760,10678,10670,10668,10738,10656,10722,10720,10680,10716,10718,10742,10766,10682,10768,10770];
    uint256[] public PD4SEpcnts = [7795,7795,7795,11692,7795,7795,11692,7795,11692,7795,7795,11692,7795,7795,7795,11692,11692,23385,7795,23385,11692,11692,23385,11692,23385,7795,7795,11692,23385,23385,23385,23385,23385,23385,93020,93020,93020,93020,93020];
        
    constructor(address _rewards, address _splits) Owned(msg.sender) {
        rewards = _rewards;
        splits = _splits;
    }

    function newFactory() public returns(address) {
        Factory factory = new Factory(rewards, splits);
        factory.updateCardsToPercent(PD2FEcards, PD2FEprcnt);
        factory.updateCardsToPercent(PD3FEcards, PD3FEpcnts);
        factory.updateCardsToPercent(PD1FEcards, PD1FEpcnts);
        factory.updateCardsToPercent(PD1ARTcards, PD1ARTpcnts);
        factory.updateCardsToPercent(PD1CBcards, PD1CBpcnts);
        factory.updateCardsToPercent(PD1SEcards, PD1SEpcnts);
        factory.updateCardsToPercent(PD2ARTcards, PD2ARTpcnts);
        factory.updateCardsToPercent(PD2CBcards, PD2CBpcnts);
        factory.updateCardsToPercent(PD2PLcards, PD2PLpcnts);
        factory.updateCardsToPercent(PD2SEcards, PD2SEpcnts);
        factory.updateCardsToPercent(PD3ARTcards, PD3ARTpcnts);
        factory.updateCardsToPercent(PD3CBcards, PD3CBpcnts);
        factory.updateCardsToPercent(PD3PLcards, PD3PLpcnts);
        factory.updateCardsToPercent(PD3SEcards, PD3SEpcnts);
        factory.updateCardsToPercent(PS15FEcards, PS15FEpcnts);
        factory.updateCardsToPercent(PS15ARTcards, PS15ARTpcnts);
        factory.updateCardsToPercent(PS15CBcards, PS15CBpcnts);
        factory.updateCardsToPercent(PS15SEcards, PS15SEpcnts);
        factory.updateCardsToPercent(PD4ARTcards, PD4ARTpcnts);
        factory.updateCardsToPercent(PD4CBcards, PD4CBpcnts);
        factory.updateCardsToPercent(PD4FEcards, PD4FEpcnts);
        factory.updateCardsToPercent(PD4SEcards, PD4SEpcnts);
        factory.setOwner(msg.sender);
        return address(factory);
    }
}
