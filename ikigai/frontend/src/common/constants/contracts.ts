export const CONTRACTS = {
  REWARDS: process.env.NEXT_PUBLIC_REWARDS_CONTRACT as string,
  NFT: process.env.NEXT_PUBLIC_NFT_CONTRACT as string,
  TOKEN: process.env.NEXT_PUBLIC_TOKEN_CONTRACT as string,
  MARKETPLACE: process.env.NEXT_PUBLIC_MARKETPLACE_CONTRACT as string,
  TREASURY: process.env.NEXT_PUBLIC_TREASURY_CONTRACT as string
} as const; 