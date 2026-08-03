// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../constants/globals.sol";
import "../interfaces/utils/IProcessorHandler.sol";
import "./AccessHandler.sol";

/**
 * @title  Processor Handler
 * @author betBase community
 * @notice A utility contract for distibuting processing to multiple contracts.
 */
abstract contract ProcessorHandler is IProcessorHandler, AccessHandler {
    // Item id => processor contract address
    mapping(uint32 => address) internal _processors;

    /**
     * @notice Adds a new processor.
     * @param id is the id of the item to process.
     * @param processorAdd is the processor contract address
     */
    function addProcessor(uint32 id, address processorAdd) external virtual onlyRole(OPERATION_ADMIN_ROLE) {
        _addProcessor(id, processorAdd);
    }

    /**
     * @notice Adds an interval of new processors.
     * @param idFrom is the lower bound id of the interval.
     * @param idFrom is the higher bound id of the interval.
     * @param processorAdd is the processor contract address
     */
    function addProcessors(
        uint32 idFrom,
        uint32 idTo,
        address processorAdd
    ) external virtual onlyRole(OPERATION_ADMIN_ROLE) {
        for (uint32 i = idFrom; i <= idTo; i++) {
            _addProcessor(i, processorAdd);
        }
    }

    /**
     * @notice Updates an existing processor.
     * @param id is the id of the item to process.
     * @param processorAdd is the processor contract address
     */
    function updateProcessor(uint32 id, address processorAdd) external virtual onlyRole(OPERATION_ADMIN_ROLE) {
        if (_processors[id] == ZERO_ADDRESS) return;
        emit ProcessorRemoved(id, _processors[id]);
        emit ProcessorAdded(id, processorAdd);
        _processors[id] = processorAdd;
    }

    /**
     * @notice Removes an existing processor.
     * @param id is the id of the item to process.
     */
    function removeProcessor(uint32 id) external virtual onlyRole(OPERATION_ADMIN_ROLE) {
        _removeProcessor(id);
    }

    /**
     * @notice Removes an interval of processors.
     * @param idFrom is the lower bound id of the interval.
     * @param idFrom is the higher bound id of the interval.
     */
    function removeProcessors(uint32 idFrom, uint32 idTo) external virtual onlyRole(OPERATION_ADMIN_ROLE) {
        for (uint32 i = idFrom; i <= idTo; i++) {
            _removeProcessor(i);
        }
    }

    /**
     * @notice Returns the processor contract address for an id.
     * @param id is the id of the item to process.
     * @return the address of related processor, 0 address if not defined.
     */
    function getProcessor(uint32 id) external view virtual returns (address) {
        return _processors[id];
    }

    /**
     * @notice Adds a new processor.
     * @param id is the id of the item to process.
     * @param processorAdd is the processor contract address
     */
    function _addProcessor(uint32 id, address processorAdd) internal virtual {
        if (_processors[id] != ZERO_ADDRESS) return;
        emit ProcessorAdded(id, processorAdd);
        _processors[id] = processorAdd;
    }

    /**
     * @notice Removes an existing processor.
     * @param id is the id of the item to process.
     */
    function _removeProcessor(uint32 id) internal virtual {
        if (_processors[id] == ZERO_ADDRESS) return;
        emit ProcessorRemoved(id, _processors[id]);
        _processors[id] = ZERO_ADDRESS;
    }
}
