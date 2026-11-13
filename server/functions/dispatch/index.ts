import { handleDispatch } from "../../src/handlers.ts";
import { createSupabaseStore } from "../_shared/supabase_store.ts";
import { createWebPushSender } from "../_shared/web_push_sender.ts";
import { serve } from "../_shared/http.ts";

// POST /dispatch, called every minute by pg_cron. Requires header x-dispatch-secret.
const store = createSupabaseStore();
const sender = createWebPushSender();
const secret = Deno.env.get("DISPATCH_SECRET");
Deno.serve((req) => serve(req, (r) => handleDispatch(r, { store, sender, secret, now: Date.now })));
