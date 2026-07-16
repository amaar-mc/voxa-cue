import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { deckPlanJsonSchema, insightJsonSchema } from "../src/schemas";

const readContract = async (fileName: string): Promise<Record<string, unknown>> => {
  const filePath = resolve(process.cwd(), "../contracts", fileName);
  const fileContents = await readFile(filePath, "utf-8");
  return JSON.parse(fileContents) as Record<string, unknown>;
};

const removeContractMetadata = (
  contract: Record<string, unknown>,
): Record<string, unknown> => {
  const {
    $schema: _schema,
    $id: _id,
    title: _title,
    ...modelSchema
  } = contract;
  return modelSchema;
};

describe("shared response contracts", () => {
  it("keeps the deck-plan Structured Output schema aligned with contracts", async () => {
    const contract = await readContract("deck-plan-v1.schema.json");

    expect(deckPlanJsonSchema).toEqual(removeContractMetadata(contract));
  });

  it("keeps the insight Structured Output schema aligned with contracts", async () => {
    const contract = await readContract("insight-v1.schema.json");

    expect(insightJsonSchema).toEqual(removeContractMetadata(contract));
  });
});
