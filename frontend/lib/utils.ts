import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function isTicketSold(bitmap: bigint, ticketIndex: number): boolean {
  if (bitmap == null) return false;
  const mask = BigInt(1) << BigInt(ticketIndex);
  return (bitmap & mask) !== BigInt(0);
}
