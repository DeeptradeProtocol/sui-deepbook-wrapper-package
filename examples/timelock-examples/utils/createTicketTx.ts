import { Transaction } from "@mysten/sui/transactions";
import { WRAPPER_PACKAGE_ID } from "../../constants";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";

export enum TicketType {
  WithdrawDeepReserves = "WithdrawDeepReserves",
  WithdrawProtocolFee = "WithdrawProtocolFee",
  WithdrawCoverageFee = "WithdrawCoverageFee",
  UpdatePoolCreationProtocolFee = "UpdatePoolCreationProtocolFee",
}

export interface CreateTicketParams {
  ticketType: TicketType;
  adminCapId: string;
  pks: number[][];
  weights: number[];
  threshold: number;
  transaction?: Transaction;
}

export function createTicketTx({ ticketType, adminCapId, pks, weights, threshold, transaction }: CreateTicketParams): {
  tx: Transaction;
  ticket: any;
} {
  const tx = transaction ?? new Transaction();

  // Get the ticket type using helper functions from Move
  const ticketTypeArg = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::${getTicketTypeHelperFunction(ticketType)}`,
    arguments: [],
  });

  const ticket = tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::wrapper::create_ticket`,
    arguments: [
      tx.object(adminCapId),
      ticketTypeArg,
      tx.pure.vector("vector<u8>", pks),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
  });

  return { tx, ticket };
}

function getTicketTypeHelperFunction(ticketType: TicketType): string {
  switch (ticketType) {
    case TicketType.WithdrawDeepReserves:
      return "withdraw_deep_reserves_ticket_type";
    case TicketType.WithdrawProtocolFee:
      return "withdraw_protocol_fee_ticket_type";
    case TicketType.WithdrawCoverageFee:
      return "withdraw_coverage_fee_ticket_type";
    case TicketType.UpdatePoolCreationProtocolFee:
      return "update_pool_creation_protocol_fee_ticket_type";
    default:
      throw new Error(`Unknown ticket type: ${ticketType}`);
  }
}
