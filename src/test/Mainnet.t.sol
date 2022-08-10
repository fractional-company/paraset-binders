// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import "../Binders.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Prime", "Prime", 18) {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TestERC1155 is ERC1155 {
    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "0");
    }

    function uri(uint256) public view override returns (string memory) {
        return "test";
    }
}

contract User is ERC1155TokenReceiver {

    Binder public art;

    constructor(address _art, address _cards) {
        art = Binder(_art);
        ERC1155(_cards).setApprovalForAll(_art, true);
    }

    function depositCard(uint256 id) public {
        art.deposit(id);
    }

    function withdrawCard(uint256 id) public {
        art.withdraw(id);
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

contract MockRewards is ERC1155TokenReceiver {
    mapping(uint256 => uint256[]) public cards;
    TestERC1155 public parallelAlpha;
    uint256 public endTimestamp;
    TestERC20 public PRIME;

    constructor(address _parallelAlpha, address _prime) {
        parallelAlpha = TestERC1155(_parallelAlpha);
        PRIME = TestERC20(_prime);

        cards[15].push(27);
        cards[15].push(28);
        cards[15].push(29);
        cards[15].push(30);
        cards[15].push(31);
        cards[15].push(33);
        cards[15].push(34);
        cards[15].push(35);
        cards[3].push(10214);
        cards[3].push(10215);
        cards[3].push(10216);
        cards[3].push(10217);
        cards[3].push(10218);
        cards[3].push(10219);
        cards[3].push(10220);
        cards[3].push(10221);
        cards[3].push(10222);
        cards[3].push(10223);
    }

    function cache(uint256 _pid, uint256) public {
        uint256[] memory amounts = new uint256[](cards[_pid].length);
        uint256[] memory ids = new uint256[](cards[_pid].length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = 1;
            ids[i] = cards[_pid][i];
        }

        parallelAlpha.safeBatchTransferFrom(
            msg.sender,
            address(this),
            ids,
            amounts,
            bytes("")
        );
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        uint256[] memory amounts = new uint256[](cards[_pid].length);
        uint256[] memory ids = new uint256[](cards[_pid].length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = 1;
            ids[i] = cards[_pid][i];
        }

        parallelAlpha.safeBatchTransferFrom(
            address(this),
            msg.sender,
            ids,
            amounts,
            bytes("")
        );
    }

    function getPoolTokenIds(uint256 _pid) public view returns(uint256[] memory) {
        return cards[_pid];
    }

    function claimPrime(uint256 _pid) public {
        PRIME.mint(msg.sender, 100000);
    }

    function setEndTimestamp(uint256 _time) public {
        endTimestamp = _time;
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

contract MockSplit {
    function createSplit(address[] calldata accounts, uint32[] calldata amounts, uint32 fee, address controller) public returns (address) {
        for (uint256 i = 0; i < accounts.length - 1; i++) {
            require(accounts[i] < accounts[i + 1], "not ordered");
        }
        uint32 sum = 0;
        for (uint256 x = 0; x < amounts.length; x++) {
            require(amounts[x] > 0, "not set");
            sum += amounts[x];
        }
        require(sum == 100000, "wrong amounts");
        return address(this);
    }
}

interface CheatCodes {
    // Set block.timestamp
    function warp(uint256) external;
    function prank(address) external;
}


contract PS15ArtTest is DSTest {

    CheatCodes public vm;

    Factory public factory;
    Binder public art;
    IERC20 public prime;
    IERC1155 public cards;

    User public user1;
    User public user2;
    User public user3;
    User public user4;
    User public user5;
    User public user6;

    uint256[] public setCards;
    uint256[] public setPercent;

    function setUp() public {
        vm = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        prime = IERC20(address(0xb23d80f5FefcDDaa212212F028021B41DEd428CF));
        cards = IERC1155(address(0x76BE3b62873462d2142405439777e971754E8E77));
        factory = new Factory(address(0xECa9D81a4dC7119A40481CFF4e7E24DD0aaF56bD), address(0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE));

        setCards.push(10666);
        setCards.push(10688);
        setCards.push(10705);
        setCards.push(10726);
        setCards.push(10746);
        setPercent.push(180000);
        setPercent.push(180000);
        setPercent.push(180000);
        setPercent.push(180000);
        setPercent.push(180000);

        factory.updateCardsToPercent(setCards, setPercent);

        art = Binder(factory.newBinder(19));

        user1 = new User(address(art), address(cards));
        // user2 = new User(address(art), address(cards));
        // user3 = new User(address(art), address(cards));
        // user4 = new User(address(art2), address(cards));
        // user5 = new User(address(art2), address(cards));
        // user6 = new User(address(art2), address(cards));

        // cards.mint(address(user1), 27, 1);
        // cards.mint(address(user1), 28, 1);
        // cards.mint(address(user1), 29, 1);
        // cards.mint(address(user1), 30, 1);
        // cards.mint(address(user2), 31, 1);
        // cards.mint(address(user2), 33, 1);
        // cards.mint(address(user2), 34, 1);
        // cards.mint(address(user2), 35, 1);
        // cards.mint(address(user3), 27, 1);
        // cards.mint(address(user3), 28, 1);
        // cards.mint(address(user3), 29, 1);
        // cards.mint(address(user3), 30, 1);
        // cards.mint(address(user3), 31, 1);
        // cards.mint(address(user3), 33, 1);
        // cards.mint(address(user3), 34, 1);
        // cards.mint(address(user3), 35, 1);

        // cards.mint(address(user4), 10214, 1);
        // cards.mint(address(user4), 10215, 1);
        // cards.mint(address(user4), 10216, 1);
        // cards.mint(address(user4), 10217, 1);
        // cards.mint(address(user5), 10218, 1);
        // cards.mint(address(user5), 10219, 1);
        // cards.mint(address(user5), 10220, 1);
        // cards.mint(address(user5), 10221, 1);
        // cards.mint(address(user6), 10222, 1);
        // cards.mint(address(user6), 10223, 1);
    }

    function testCache() public {
        vm.prank(0x98a2c0E2F9E7E35C7d4924B456AB413d250aC73B);
        cards.setApprovalForAll(address(art), true);
        vm.prank(0x98a2c0E2F9E7E35C7d4924B456AB413d250aC73B);
        art.deposit(10666);
        vm.prank(0x98a2c0E2F9E7E35C7d4924B456AB413d250aC73B);
        art.deposit(10688);
        vm.prank(0x98a2c0E2F9E7E35C7d4924B456AB413d250aC73B);
        art.deposit(10705);
        vm.prank(0x98a2c0E2F9E7E35C7d4924B456AB413d250aC73B);
        art.deposit(10726);
        vm.prank(0x98a2c0E2F9E7E35C7d4924B456AB413d250aC73B);
        art.deposit(10746);
    }


    // function test_UncacheTimestamp() public {
    //     user1.depositCard(27);
    //     user1.depositCard(28);
    //     user1.depositCard(29);
    //     user1.depositCard(30);
    //     user2.depositCard(31);
    //     user2.depositCard(33);
    //     user2.depositCard(34);
    //     user2.depositCard(35);

    //     rewards.setEndTimestamp(block.timestamp + 5 days);
    //     vm.warp(block.timestamp + 6 days);

    //     art.uncache();
    // }

    // function test_claimPrime() public {
    //     art.claimPrime();
    //     assertEq(prime.balanceOf(address(art)), 100000);

    //     art.splitPrime();
    //     assertEq(prime.balanceOf(address(art.split())), 100000);
    // }
}
