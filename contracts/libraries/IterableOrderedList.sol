//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IterableOrderedList
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
            // if the element after zero is zero, the list is empty
            // so we place this element between zero and zero
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
            // get the given position
            tempPosition = getPosition(self, afterPosition, true, true);

            // first make sure the given afterPosition has not been removed
            // between the time when the tx was made and its inclusion in the chain
            if (tempPosition.next == zero && tempPosition.prev == zero) {
                // @TODO: what to do if tempPosition was removed?!
            }

            // then let's make sure we didn't get the position wrong
            // we might have an item that should be higher in rank than afterPosition
            if (value > tempPosition.value) {
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
            } else {
                // else make sure the given position is the good one

                // first set the value to position our new item after afterPosition
                prevId = afterPosition;
                nextId = tempPosition.next;

                // then try to go down the list to find where we actually belong
                tempPosition = getPosition(self, nextId, false, true);
                while (tempPosition.value >= value) {
                    prevId = nextId;
                    nextId = tempPosition.next;
                    // we don't need prev here, since we already have it
                    tempPosition = getPosition(self, nextId, false, true);
                }
            }
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
