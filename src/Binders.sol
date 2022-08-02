// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Owned} from "solmate/auth/Owned.sol";

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

contract Binder is ERC1155TokenReceiver, Owned {

    event Deposit(address indexed user, uint256 cardId);
    event Withdraw(address indexed user, uint256 cardId);
    event Cached();

    // 0xECa9D81a4dC7119A40481CFF4e7E24DD0aaF56bD
    IPrimeRewards public immutable CACHING;
    // 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE
    ISplitMain public immutable SPLITS;
    uint256[] public cards;

    address public split;
    uint256 public immutable pid;
    uint256 public totalCardsNeeded = 0;
    uint256 public totalCardsDeposited = 0;
    
    enum Stages{Setup, Cached, Finished}
    Stages public stage;

    // The cards in the set
    mapping(uint256 => bool) cardInSet;
    // The owners of cards in the set
    mapping(uint256 => address) cardToOwner;

    constructor(address _owner, address _rewards, address _splits, uint256 _pid, uint256[] memory _cards) Owned(_owner) {
        CACHING = IPrimeRewards(_rewards);
        SPLITS = ISplitMain(_splits);
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

    modifier isFinished() {
        require(stage == Stages.Finished, "not finished");
        _;
    }

    /// @notice Deposit a card from the set. Requires that we are not locked.
    /// @param cardId The id of the card we want to deposit.
    function deposit(uint256 cardId) public isSetup {
        require(cardToOwner[cardId] == address(0), "already deposited");
        require(cardInSet[cardId], "not in set");
        cardToOwner[cardId] = msg.sender;
        IERC1155(CACHING.parallelAlpha()).safeTransferFrom(msg.sender, address(this), cardId, 1, "0x0");
        totalCardsDeposited++;
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
        emit Withdraw(msg.sender, cardId);
    }

    /// @notice Attempt to cache. Will only work if we have all the cards needed.
    function _cache() internal {        
        address[] memory accounts = new address[](cards.length + 1);
        uint32[] memory percentAllocations = new uint32[](cards.length + 1);
        for (uint256 x = 0; x < cards.length; x++) {
            accounts[x] = cardToOwner[cards[x]];
            percentAllocations[x] = uint32(100000) / uint32(cards.length+1);
        }
        accounts[cards.length] = owner;
        percentAllocations[cards.length] = 100000 - (100000 / uint32(cards.length+1) * uint32(cards.length));
        split = SPLITS.createSplit(accounts, percentAllocations, 0, address(this));
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

    function emergencyUncache() public onlyOwner {
        CACHING.withdraw(pid, 1);
    }

    function emergencyWithdrawNFT(address nft, address to, uint256 id, uint256 amount) public onlyOwner {
        IERC1155(nft).safeTransferFrom(address(this), to, id, amount, "0");
    }

    function emergencyWithdrawToken(address token, address to, uint256 amount) public onlyOwner {
        IERC20(token).transfer(to, amount);
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

contract Factory is Owned {

    event NewBinder(uint256 pid, address addr);

    address public rewards;
    address public splits;

    constructor(address _rewards, address _splits) Owned(msg.sender) {
        rewards = _rewards;
        splits = _splits;
    }

    function newBinder(uint256 pid) public returns(Binder){
        uint256[] memory ids = IPrimeRewards(rewards).getPoolTokenIds(pid);
        Binder binder = new Binder(owner, rewards, splits, pid, ids);
        emit NewBinder(pid, address(binder));
        return binder;
    }
}
