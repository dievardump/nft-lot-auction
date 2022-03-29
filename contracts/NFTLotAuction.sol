//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './libraries/IterableOrderedList.sol';

/// @title NFTLotAuction
/// @author Simon Fremaux (@dievardump)
contract NFTLotAuction {
    using IterableOrderedList for IterableOrderedList.List;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    event AuctionCreated(uint256 auctionId);
    event AuctionSettled(
        uint256 auctionId,
        uint256 accumulation,
        uint256 bottomValue
    );

    // last auction id used
    uint256 lastAuctionId;

    // all auctions
    mapping(uint256 => Auction) public auctions;

    // list of bids for one auction
    mapping(uint256 => IterableOrderedList.List) internal auctionBids;

    // list of bids for one user on a auction
    mapping(address => mapping(uint256 => EnumerableSet.Bytes32Set))
        internal userBidsPerAuction;

    // consumed orders per auction
    mapping(uint256 => mapping(bytes32 => bool)) internal auctionConsumedOrders;

    // last known user id
    uint64 public lastUserId;

    // user ids
    mapping(address => uint64) public userAddressToId;
    mapping(uint64 => address) public userIdToAddress;

    struct Auction {
        address creator;
        uint96 minValuePerItem;
        address consumer;
        uint96 maxAmountPerBid;
        bool uniqBid;
        bool settled;
        bool canIncrease;
        // if the end price for each token is the last bid price
        // or if each bid will get their token at the price they gave
        bool meetPrice;
        uint256 maxSupply;
        uint256 accumulation; // set after settled
        uint256 start;
        uint256 deadline;
        bytes32 lastValidOrderId; // this in case we have several orders with same value
    }

    /// @notice Allows to create an auction for a lot(maxSupply) of NFTs
    /// @param maxSupply how many NFTs in the lot
    /// @param minValuePerItem the minimum bid value
    /// @param maxAmountPerBid the maximum items people can ask for in a bid
    /// @param start when the bidding starts
    /// @param deadline when the bidding ends
    /// @param uniqBid if users are restricted to one order in the auction
    /// @param canIncrease if users can increase their bid with a new transaction
    /// @param consumer the contract having the right to "consume" bids once the auction is settled
    /// @param meetPrice if the price per token at the end is the same for all bids, or each bid pays the bidded value
    function createAuction(
        uint256 maxSupply, // how many items are to be sold
        uint96 minValuePerItem, // the minimum price per item
        uint96 maxAmountPerBid, // how many items users can bid for at once
        uint256 start, // when does the bidding starts
        uint256 deadline, // when does the bidding ends
        bool uniqBid, // true means users can not do another bid once they did one
        bool canIncrease, // if bidders can increase their bid instead of having to create new ones
        address consumer, // the contract that has the right to "consume" the bids
        bool meetPrice // if the price per token choosen at the end is the same for everyone
    ) external returns (uint256) {
        uint256 auctionId = (++lastAuctionId);
        auctions[auctionId] = Auction({
            creator: msg.sender,
            minValuePerItem: minValuePerItem,
            maxAmountPerBid: maxAmountPerBid,
            start: start,
            deadline: deadline,
            consumer: consumer,
            uniqBid: uniqBid,
            meetPrice: meetPrice,
            canIncrease: canIncrease,
            lastValidOrderId: bytes32(0),
            accumulation: 0,
            settled: false,
            maxSupply: maxSupply
        });

        emit AuctionCreated(auctionId);

        return auctionId;
    }

    /// @notice  this allows to place an order for a given auction
    // function placeOrders(
    //     uint256 auctionId,
    //     uint96[] memory values,
    //     uint96[] memory amounts,
    //     // this needs to be calculated before the call to this method
    //     // using the view `findPosition(auctionId, value)`
    //     bytes32[] memory afterPositions
    // ) external payable {
    //     Auction memory auction = auctions[auctionId];
    //     require(auction.deadline >= block.timestamp, '!AUCTION_ENDED!');

    //     require(
    //         values.length == amounts.length &&
    //             afterPositions.length == values.length,
    //         '!LENGTH_MISMATCH!'
    //     );

    //     address sender = msg.sender;
    //     uint64 userId = _findOrCreateUser(sender);

    //     EnumerableSet.Bytes32Set storage userBids = userBidsPerAuction[sender][
    //         auctionId
    //     ];

    //     IterableOrderedList.List storage list = auctionBids[auctionId];

    //     // some auctions only allow one bid per user.
    //     require(
    //         auction.uniqBid == false ||
    //             (userBids.length() == 0 && values.length == 1),
    //         '!ONLY_ONE_BID!'
    //     );

    //     uint256 total;
    //     bytes32 orderId;
    //     for (uint256 i; i < values.length; i++) {
    //         require(values[i] > 0 && amounts[i] > 0, '!NO_ZERO_VALUES!');
    //         require(values[i] >= auction.minValuePerItem, '!WRONG_VALUE!');

    //         total += uint256(values[i] * amounts[i]);
    //         orderId = IterableOrderedList.encodeOrder(
    //             userId,
    //             amounts[i],
    //             values[i]
    //         );

    //         // ensure a user doesn't create the same bid again
    //         require(userBids.add(orderId), '!BID_EXISTS!');

    //         // insert afterPosition
    //         list.insertAfter(orderId, afterPositions[i]);
    //     }

    //     // make sure the bids are backed by value
    //     require(total > 0 && msg.value == total, '!WRONG_VALUE!');
    // }

    // / @notice This allows a user to add value to orders they already made
    // /         This allows to increase precedent orders instead of redoing new
    // function addToOrders(
    //     uint256 auctionId,
    //     bytes32[] memory orderIds,
    //     uint96[] memory valuesToAdd,
    //     // this needs to be calculated before the call to this method
    //     // using the view `findPosition(auctionId, value)`
    //     bytes32[] memory afterPositions
    // ) external payable {
    //     Auction memory auction = auctions[auctionId];
    //     require(auction.deadline >= block.timestamp, '!AUCTION_ENDED!');
    //     require(auction.canIncrease, '!NO_INCREASE!');

    //     require(
    //         orderIds.length == valuesToAdd.length &&
    //             orderIds.length == afterPositions.length,
    //         '!LENGTH_MISMATCH!'
    //     );

    //     address sender = msg.sender;
    //     uint64 userId = _findOrCreateUser(sender);

    //     EnumerableSet.Bytes32Set storage userBids = userBidsPerAuction[sender][
    //         auctionId
    //     ];

    //     IterableOrderedList.List storage list = auctionBids[auctionId];

    //     uint256 total;
    //     bytes32 orderId;
    //     uint96 oldAmount;
    //     uint96 oldValue;
    //     for (uint256 i; i < valuesToAdd.length; i++) {
    //         require(valuesToAdd[i] > 0, '!NO_ZERO_VALUES!');

    //         // remove order from the user list
    //         // remove returns true only if the element existed; this saves a check
    //         require(userBids.remove(orderIds[i]), '!UNKNOWN_ORDER!');

    //         // get old order value and amount
    //         (, oldAmount, oldValue) = IterableOrderedList.decodeOrder(
    //             orderIds[i]
    //         );

    //         // we need to ensure the value sent is sent for each item of the order
    //         total += uint256(valuesToAdd[i] * oldAmount);

    //         // remove old order
    //         list.remove(orderIds[i]);

    //         // create new orderId
    //         orderId = IterableOrderedList.encodeOrder(
    //             userId,
    //             oldAmount,
    //             oldValue + valuesToAdd[i]
    //         );

    //         // ensure a user doesn't create the same bid again
    //         require(userBids.add(orderId), '!BID_EXISTS!');

    //         // insert afterPosition
    //         list.insertAfter(orderId, afterPositions[i]);
    //     }

    //     // make sure the bids increases are backed by value
    //     require(total > 0 && msg.value == total, '!WRONG_VALUE!');
    // }

    /// @notice  this allows to place an order for a given auction
    function placeOrder(
        uint256 auctionId,
        uint96 value,
        uint96 amount,
        // this needs to be calculated before the call to this method
        // using the view `findPosition(auctionId, value)`
        bytes32 afterPosition
    ) external payable {
        Auction memory auction = auctions[auctionId];
        require(auction.deadline >= block.timestamp, '!AUCTION_ENDED!');

        address sender = msg.sender;
        uint64 userId = _findOrCreateUser(sender);

        EnumerableSet.Bytes32Set storage userBids = userBidsPerAuction[sender][
            auctionId
        ];

        IterableOrderedList.List storage list = auctionBids[auctionId];

        // some auctions only allow one bid per user.
        require(
            auction.uniqBid == false || userBids.length() == 0,
            '!ONLY_ONE_BID!'
        );

        require(value > 0 && amount > 0, '!NO_ZERO_VALUES!');
        require(
            value >= auction.minValuePerItem &&
                msg.value == uint256(value * amount),
            '!WRONG_VALUE!'
        );

        bytes32 orderId = IterableOrderedList.encodeOrder(
            userId,
            amount,
            value
        );

        // ensures a user doesn't create the same bid again
        require(userBids.add(orderId), '!BID_EXISTS!');

        // insert afterPosition
        list.insertAfter(orderId, afterPosition);
    }

    /// @notice This allows a user to add value to orders they already made
    ///         This allows to increase precedent orders instead of redoing new
    function addToOrder(
        uint256 auctionId,
        bytes32 orderId,
        uint96 valueToAdd,
        // this needs to be calculated before the call to this method
        // using the view `findPosition(auctionId, value)`
        bytes32 afterPosition
    ) external payable {
        Auction memory auction = auctions[auctionId];
        require(auction.deadline >= block.timestamp, '!AUCTION_ENDED!');
        require(auction.canIncrease, '!NO_INCREASE!');

        address sender = msg.sender;
        uint64 userId = _findOrCreateUser(sender);

        EnumerableSet.Bytes32Set storage userBids = userBidsPerAuction[sender][
            auctionId
        ];

        IterableOrderedList.List storage list = auctionBids[auctionId];

        // make sure the bid increase are backed by value
        require(valueToAdd > 0 && msg.value == valueToAdd, '!WRONG_VALUE!');

        // remove order from the user list
        // remove returns true only if the element existed; this saves a check
        require(userBids.remove(orderId), '!UNKNOWN_ORDER!');

        // get old order value and amount
        (, uint96 oldAmount, uint96 oldValue) = IterableOrderedList.decodeOrder(
            orderId
        );

        // remove old order
        list.remove(orderId);

        // create new orderId
        orderId = IterableOrderedList.encodeOrder(
            userId,
            oldAmount,
            oldValue + valueToAdd
        );

        // ensure this new order id didn't already exist
        require(userBids.add(orderId), '!BID_EXISTS!');

        // insert afterPosition
        list.insertAfter(orderId, afterPosition);
    }

    /// @notice Helpers that allows to find the position of an order (by its value) for a given auction
    /// @param auctionId the auction
    /// @param value the order value per item
    /// @return the order id that this new order should follow
    function findPosition(uint256 auctionId, uint96 value)
        external
        view
        returns (bytes32)
    {
        Auction memory auction = auctions[auctionId];
        require(auction.maxSupply != 0, '!UNKNWON_AUCTION');

        IterableOrderedList.List storage list = auctionBids[auctionId];

        // we start with zero
        IterableOrderedList.OrderPosition memory selected = list.getPosition(
            bytes32(0),
            false,
            true
        );

        // and we select the next, and the next and the next
        // until our value is greater than the selected item
        do {
            selected = list.getPosition(selected.next, true, true);
        } while (value <= selected.value);

        // then we have to come just before this item
        return selected.prev;
    }

    /// @notice Allows an auction.consumer to "consume" an order, once the auction is settled
    ///         Usually this would be called by the contract minting the NFTs, after the bidder
    ///         (which should be `operator`) asks for their order to be consumed
    ///         Something like:
    ///         User -> MintingContract.mint -> NFTLotAuction.consume (which returns the amount of tokens to mint)
    /// @param auctionId the auction Id
    /// @param orderId the order id
    /// @param operator the address claiming to be the order creator
    /// @param recipient the address that should get the value of the bid
    /// @return itemsReceived the number of items corresponding to this order
    function consumeOrder(
        uint256 auctionId,
        bytes32 orderId,
        address operator,
        address recipient
    ) external returns (uint256 itemsReceived) {
        require(
            auctionConsumedOrders[auctionId][orderId] == false,
            '!ALREADY_CONSUMED!'
        );

        Auction memory auction = auctions[auctionId];

        // verifies that the auction has been settled
        require(auction.settled, '!NOT_SETTLED!');

        // only contract set as "consumer" on a auction can consume a bid
        require(auction.consumer == msg.sender, '!NOT_ALLOWED!');

        (
            uint64 bidderId,
            uint96 bidAmount,
            uint96 bidValue
        ) = IterableOrderedList.decodeOrder(orderId);

        address bidder = userById(bidderId);

        // verify order is from operator
        require(
            bidder == operator && operator != address(0),
            '!WRONG_ADDRESS!'
        );

        IterableOrderedList.List storage list = auctionBids[auctionId];
        (, , uint96 bottomValue) = IterableOrderedList.decodeOrder(
            auction.lastValidOrderId
        );

        // verifies the order is a valid order (value >= bottomValue && (order.next != 0 || orderId == lastId)
        require(
            bidValue >= bottomValue &&
                (orderId == auction.lastValidOrderId ||
                    list.nextMap[orderId] != bytes32(0)),
            '!INVALID_ORDER!'
        );

        // set order as consumed, this also blocks reEntrancy
        auctionConsumedOrders[auctionId][orderId] = true;

        // depending on the auction type, the pricePerItem is either the "meet value" or the actual bid value
        uint256 pricePerItem = uint256(
            auction.meetPrice ? bottomValue : bidValue
        );

        // first we consider the user will receive as much they bid for
        itemsReceived = uint256(bidAmount);

        // However if the order is the last order selected, and it can't fit in the full lot
        // we reduce the amount they receive, to fit the lot
        if (
            orderId == auction.lastValidOrderId &&
            auction.accumulation > auction.maxSupply
        ) {
            // if accumulated is too big, it means the last accepted order doesn't fit completly in the auction
            // therefore we need to send back part of the ethereum to the bidder
            // and only consume the part that fits in the order
            itemsReceived -= (auction.accumulation - auction.maxSupply);
        }

        // calculate how much the user is actually supposed to pay, now that we know exactly
        // how many items they get, and the exact price per item
        uint256 toPay = pricePerItem * itemsReceived;
        uint256 payed = uint256(bidValue) * uint256(bidAmount);

        // if the user has payed more than what they will get, we send them the difference
        if (payed > toPay) {
            (bool success1, ) = bidder.call{value: payed - toPay}('');
            require(success1, '!ERROR_TRANSFER_VALUE');
        }

        // transfer bid value to recipient
        (bool success2, ) = recipient.call{value: toPay}('');
        require(success2, '!ERROR_TRANSFER_VALUE');
    }

    /// @notice Settling an order (finding the last order valid that goes into an auction)
    /// @param auctionId the auction
    function settle(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        IterableOrderedList.List storage list = auctionBids[auctionId];

        // require ended
        require(
            auctions[auctionId].deadline >= block.timestamp,
            '!AUCTION_ONGOING!'
        );

        (
            bytes32 lastValidOrderId,
            uint96 bottomValue,
            uint256 accumulation
        ) = findAuctionBottom(auctionId);

        // save accumulation, because it's possible we didn't sell everything or that accumulation
        // is a bit more than maxSupply.
        // for example if the last bid is valid but its full amount can not be fully fulfilled,
        // we will have to refund the difference (accumulation - maxSupply) at the time the bid is consumed
        auction.accumulation = accumulation;
        auction.lastValidOrderId = lastValidOrderId;

        // then we will try to see if there are following Order with the exact same value.
        // if yes, we need to "invalidate" them by setting next to zero
        // this way if someone tries to consume an orderId with value == bottomValue
        // we will make sure it's either the lastValidOrderId or it hasn't next == zero
        uint96 value;
        bytes32 zero;
        bytes32 temp;
        bytes32 nextOrderId = list.nextMap[lastValidOrderId];
        while (nextOrderId != zero) {
            (, , value) = IterableOrderedList.decodeOrder(nextOrderId);
            // if the value is the same as the bottom value
            if (value == bottomValue) {
                temp = nextOrderId;
                // invalidate the order by setting next to 0
                list.nextMap[nextOrderId] = zero;
                nextOrderId = temp;
            } else {
                break;
            }
        }

        auction.settled = true;
        emit AuctionSettled(auctionId, accumulation, bottomValue);
    }

    /// @notice Helps to find the last valid order going into an auction lot
    /// @param auctionId the auction to find the "bottom"
    /// @return lastOrderId the last valid order id
    /// @return bottomValue the bottom value
    /// @return accumulation how many NFTs fit in the order
    function findAuctionBottom(uint256 auctionId)
        public
        view
        returns (
            bytes32 lastOrderId,
            uint96 bottomValue,
            uint256 accumulation
        )
    {
        Auction memory auction = auctions[auctionId];
        IterableOrderedList.List storage list = auctionBids[auctionId];

        bytes32 zero;

        // start with the first
        bytes32 currentOrderId = list.nextMap[zero];
        uint96 amount;

        while (accumulation < auction.maxSupply && currentOrderId != zero) {
            // get bottomValue and amount
            (, amount, bottomValue) = IterableOrderedList.decodeOrder(
                currentOrderId
            );
            // add to values
            accumulation += uint256(amount);

            lastOrderId = currentOrderId;
            currentOrderId = list.nextMap[currentOrderId];
        }
    }

    /// @notice Helpers to get an address from an user id (encoded in the order id)
    /// @param userId the userId
    /// @return user the user address
    function userById(uint64 userId) public view returns (address user) {
        user = userIdToAddress[userId];
        require(user != address(0), '!UNKNOWN_USER!');
        return user;
    }

    /// @dev return an user id (creates it if does not exist)
    /// @param user the user address
    /// @return userId the user id
    function _findOrCreateUser(address user) internal returns (uint64 userId) {
        userId = userAddressToId[user];

        if (userId == uint64(0)) {
            userId = (++lastUserId);
            userAddressToId[user] = userId;
            userIdToAddress[userId] = user;
        }
    }
}
