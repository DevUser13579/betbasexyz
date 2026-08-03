// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IProcessorHandler {
    /**
     * @notice Event that fires when a processor is added.
     * @param id is the id of the item to process.
     * @param processorAdd is the processor contract address.
     */
    event ProcessorAdded(uint32 id, address processorAdd);

    /**
     * @notice Event that fires when a processor is removed.
     * @param id is the id of the item to process.
     * @param processorAdd is the processor contract address.
     */
    event ProcessorRemoved(uint32 id, address processorAdd);

    function addProcessor(uint32, address) external;
    function addProcessors(uint32, uint32, address) external;
    function updateProcessor(uint32, address) external;
    function removeProcessor(uint32) external;
    function removeProcessors(uint32, uint32) external;
    function getProcessor(uint32) external view returns(address);
}
