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

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "UNAUTHORIZED");
        _;
    }

    modifier isSetup() {
        require(stage == Stages.Setup, "not setup");
        _;
    }

    modifier isCached() {
        require(stage == Stages.Cached, "not cached");
        _;
    }

    modifier isFinished() {
        require(stage == Stages.Finished, "not finished");
        _;
    }

    function getAddressPercent(address user) public view returns(uint256) {
        return addressToPercent.get(user);
    }

    function setOwner(address newOwner) public onlyOwner {
        owner = newOwner;

        emit OwnerUpdated(msg.sender, newOwner);
    }

    /// @notice Deposit a card from the set. Requires that we are not locked.
    /// @param cardId The id of the card we want to deposit.
    function deposit(uint256 cardId) public isSetup {
        require(cardToOwner[cardId] == address(0), "already deposited");
        require(cardInSet[cardId], "not in set");
        cardToOwner[cardId] = msg.sender;
        IERC1155(CACHING.parallelAlpha()).safeTransferFrom(msg.sender, address(this), cardId, 1, "0x0");
        totalCardsDeposited++;

        uint256 percents = FACTORY.cardsToPercent(cardId);
        (, uint256 total) = addressToPercent.tryGet(msg.sender);
        addressToPercent.set(msg.sender, total + percents);

        if (totalCardsDeposited == totalCardsNeeded) {
            _cache();
        }
        emit Deposit(msg.sender, cardId);
    }

    /// @notice Withdraw a card from the set. Requires we are not locked.
    /// @param cardId The id of the card we want to withdraw.
    function withdraw(uint256 cardId) public isSetup {
        require(cardToOwner[cardId] == msg.sender, "not owner");
        IERC1155(CACHING.parallelAlpha()).safeTransferFrom(address(this), msg.sender, cardId, 1, "0x0");
        cardToOwner[cardId] = address(0);
        totalCardsDeposited--;

        uint256 percents = FACTORY.cardsToPercent(cardId);
        (, uint256 total) = addressToPercent.tryGet(msg.sender);
        addressToPercent.set(msg.sender, total - percents);
  
        emit Withdraw(msg.sender, cardId);
    }

    /// @notice Attempt to cache. Will only work if we have all the cards needed.
    function _cache() internal {    
        address[] memory accounts = new address[](addressToPercent.length() + 1);
        uint32[] memory percentAllocations = new uint32[](addressToPercent.length() + 1);
        uint256 percentTotal = 0;
        for (uint256 x = 0; x < addressToPercent.length(); x++) {
            (address tempAddr,uint256 percent) = addressToPercent.at(x);
            accounts[x] = tempAddr;
            percentTotal += percent;
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

    /// @notice Uncache all NFTs and send them back to their owners
    function uncache() public isCached {
        _finish();
        CACHING.withdraw(pid, 1);
        for (uint256 x = 0; x < cards.length; x++) {
            IERC1155(CACHING.parallelAlpha()).safeTransferFrom(address(this), cardToOwner[cards[x]], cards[x], 1, "0");
        }
    }

    /// @notice Unlock the vault. Can be one in three ways. By owner, staking ends, 1 year.
    function _finish() internal {
        if (msg.sender == owner) {
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

    function claimPrimeEvent(address claimAddress, uint256 claimAmount, uint256 index, uint256 maximumAmount, bytes32[] calldata merkleProof) public {
        IPrimeEvent(claimAddress).claim(claimAmount, index, maximumAmount, merkleProof);
    }

    function emergencyUncache() public onlyOwner {
        CACHING.withdraw(pid, 1);
    }

    function emergencyWithdrawNFT(address nft, address to, uint256 id, uint256 amount) public onlyOwner {
        IERC1155(nft).safeTransferFrom(address(this), to, id, amount, "0");
    }

    function emergencyWithdrawToken(address token, address to, uint256 amount) public onlyOwner {
        IERC20(token).transfer(to, amount);
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
        address,
        uint256,
        uint256,
        bytes calldata
    ) external virtual override returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual override returns (bytes4) {
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

    mapping(uint256 => uint256) public cardsToPercent;

    constructor(address _rewards, address _splits) Owned(msg.sender) {
        rewards = _rewards;
        splits = _splits;
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
}
