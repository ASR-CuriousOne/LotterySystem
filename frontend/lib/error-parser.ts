import { BaseError, ContractFunctionRevertedError } from "viem";

export function getContractErrorMessage(err: unknown): string {
  if (err instanceof BaseError) {
    const revertError = err.walk(
      (error) => error instanceof ContractFunctionRevertedError,
    );

    if (revertError instanceof ContractFunctionRevertedError) {
      const errorName = revertError.data?.errorName;

      switch (errorName) {
        case "Lottery__InvalidPhase":
          return "This action cannot be performed in the current phase.";
        case "Lottery__IncorrectTicketPrice":
          return "The amount of ETH sent does not match the ticket price.";
        case "Lottery__HashMismatch":
          return "The secret phrase provided does not match the committed hash.";
        case "Lottery__TicketAlreadySold":
          return "This ticket number has already been purchased by someone else.";
        case "Lottery__SoldOut":
          return "All 256 tickets for this round have been sold.";
        case "Lottery__NoParticipants":
          return "The sale cannot be closed because no tickets were sold.";
        case "Lottery__NotWinner":
          return "Only the winning address is authorized to claim this prize.";
        case "Lottery__NoFundsToWithdraw":
          return "You have no pending prize balance to withdraw.";
        default:
          return `Contract error: ${errorName || "Unknown Revert"}`;
      }
    }

    return err.shortMessage || "A network error occurred.";
  }

  return "An unexpected error occurred.";
}
