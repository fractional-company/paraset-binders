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

interface CheatCodes {
    // Set block.timestamp
    function warp(uint256) external;
    function createFork(string calldata urlOrAlias) external returns (uint256);
}


contract PS15ArtTest is DSTest {

    CheatCodes public vm;

    Factory public factory;
    Binder public art;
    Binder public art2;

    User public user1;
    User public user2;
    User public user3;
    User public user4;
    User public user5;
    User public user6;

    uint256 mainnetFork;

    uint256[] public setCards;
    uint256[] public setPercent;

    function setUp() public {
        vm = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        mainnetFork = vm.createFork("https://eth-mainnet.g.alchemy.com/v2/VUKL7vgCcWUWCO_gnOMCDPDEUy5BsFFe");
        // address rewards = address(0xECa9D81a4dC7119A40481CFF4e7E24DD0aaF56bD);
        // address split = address(0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE);
        // factory = new Factory(address(rewards), address(split));

        // setCards.push(10627);
        // setCards.push(10645);
        // setCards.push(10625);
        // setCards.push(10490);
        // setCards.push(10628);
        // setCards.push(10629);
        // setPercent.push(2432);
        // setPercent.push(7297);
        // setPercent.push(7297);
        // setPercent.push(14595);
        // setPercent.push(29189);
        // setPercent.push(29189);

        // setCards.push(27);
        // setCards.push(28);
        // setCards.push(29);
        // setCards.push(30);
        // setCards.push(31);
        // setCards.push(33);
        // setCards.push(34);
        // setCards.push(35);
        // setPercent.push(11250);
        // setPercent.push(11250);
        // setPercent.push(11250);
        // setPercent.push(11250);
        // setPercent.push(11250);
        // setPercent.push(11250);
        // setPercent.push(11250);
        // setPercent.push(11250);

        // setCards.push(10214);
        // setCards.push(10215);
        // setCards.push(10216);
        // setCards.push(10217);
        // setCards.push(10218);
        // setCards.push(10219);
        // setCards.push(10220);
        // setCards.push(10221);
        // setCards.push(10222);
        // setCards.push(10223);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);
        // setPercent.push(9000);

        // factory.updateCardsToPercent(setCards, setPercent);


        // art = Binder(factory.newBinder(15));
        // art2 = Binder(factory.newBinder(3));

        // user1 = new User(address(art), address(0x76BE3b62873462d2142405439777e971754E8E77));
        // user2 = new User(address(art), address(0x76BE3b62873462d2142405439777e971754E8E77));
        // user3 = new User(address(art), address(0x76BE3b62873462d2142405439777e971754E8E77));
        // user4 = new User(address(art2), address(0x76BE3b62873462d2142405439777e971754E8E77));
        // user5 = new User(address(art2), address(0x76BE3b62873462d2142405439777e971754E8E77));
        // user6 = new User(address(art2), address(0x76BE3b62873462d2142405439777e971754E8E77));

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
        user1.depositCard(27);
        user1.depositCard(28);
        user1.depositCard(29);
        user1.depositCard(30);
        user2.depositCard(31);
        user2.depositCard(33);
        user2.depositCard(34);
        user2.depositCard(35);
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
}
