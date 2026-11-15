"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

export async function markAllRead(): Promise<ActionResult> {
  try {
    await api("/v1/notifications/read-all", { method: "POST", query: { app: "admin" } });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/", "layout");
  return { ok: true, message: "Notifications marquées comme lues." };
}
