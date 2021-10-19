//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title GasWarKiller
/// @author Simon Fremaux (@dievardump)

library IterableOrderedList {
    // convenient struct used when ordering list
    struct OrderPosition {
        bytes32 id;
        bytes32 prev;
        bytes32 next;
        uint96 value;
    }

    struct List {
        mapping(bytes32 => bytes32) nextMap;
        mapping(bytes32 => bytes32) prevMap;
    }

    // order = { owner, value, amount } => into Bytes
    // orders = bytes32[]
    // orderPosition = { previousId, nextId }
    // positions = uint256[]
    function getPosition(
        List storage self,
        bytes32 orderId,
        bool includePrev,
        bool includeNext
    ) internal view returns (OrderPosition memory) {
        (, , uint96 value) = decodeOrder(orderId);
        return
            OrderPosition({
                id: orderId,
                prev: includePrev ? self.prevMap[orderId] : bytes32(0),
                next: includeNext ? self.nextMap[orderId] : bytes32(0),
                value: value
            });
    }

    function insertAfter(
        List storage self,
        bytes32 orderId,
        bytes32 afterPosition
    ) internal {
        bytes32 zero;
        bytes32 nextId;
        bytes32 prevId;

        (, , uint96 value) = decodeOrder(orderId);

        OrderPosition memory tempPosition;
        // insert as first element
        if (afterPosition == zero) {
            // first ever element to be inserted
            if (self.nextMap[zero] == zero) {
                nextId = zero;
                prevId = zero;
            } else {
                // else this means at time of sending the tx
                // this order was supposed to be the highest order
                // so the current first is supposed to be our next
                nextId = self.nextMap[zero];
                prevId = zero;
                tempPosition = getPosition(self, nextId, false, true);

                // However, between the tx was emitted, and the time it was included
                // it is possible that other orders, higher than the current, came in between
                // or that someone didn't calculate the afterPosition and went with 0 (not recommended)
                // so right now we try to find prevId and nextId for current order
                // by looking for the position with a value smaller than order
                while (tempPosition.value >= value) {
                    prevId = nextId;
                    nextId = tempPosition.next;
                    // we don't need prev here, since we already have it
                    tempPosition = getPosition(self, nextId, false, true);
                }
            }
        } else {
            tempPosition = getPosition(self, afterPosition, true, false);
            // for some weird reason, it is possible that afterPosition was badly calculated
            // so just in case, let's find the right previous by going up in the list
            while (value > tempPosition.value) {
                tempPosition = getPosition(
                    self,
                    tempPosition.prev,
                    true,
                    false
                );
            }

            prevId = tempPosition.id;
            nextId = self.nextMap[prevId];
        }

        // here we should have the right nextId and prevId to place our order

        // we are the new next of prevId
        self.nextMap[prevId] = orderId;

        // prevId is our previous
        self.prevMap[orderId] = prevId;

        // nextId is our next
        self.nextMap[orderId] = nextId;

        // and we are now previous of nextId
        self.prevMap[nextId] = orderId;
    }

    function remove(List storage self, bytes32 orderId) internal {
        bytes32 nextId = self.nextMap[orderId];
        bytes32 prevId = self.prevMap[orderId];

        // change previous on next order in the list
        self.prevMap[nextId] = prevId;
        // change next on previous order in the list
        self.nextMap[prevId] = nextId;

        // set previous and next to 0 for current order
        self.prevMap[orderId] = bytes32(0);
        self.nextMap[orderId] = bytes32(0);
    }

    function decodeOrder(bytes32 _orderData)
        internal
        pure
        returns (
            uint64 userId,
            uint96 buyAmount,
            uint96 sellAmount
        )
    {
        // Note: converting to uint discards the binary digits that do not fit
        // the type.
        userId = uint64(uint256(_orderData) >> 192);
        buyAmount = uint96(uint256(_orderData) >> 96);
        sellAmount = uint96(uint256(_orderData));
    }

    function encodeOrder(
        uint64 userId,
        uint96 buyAmount,
        uint96 sellAmount
    ) internal pure returns (bytes32) {
        return
            bytes32(
                (uint256(userId) << 192) +
                    (uint256(buyAmount) << 96) +
                    uint256(sellAmount)
            );
    }
}
