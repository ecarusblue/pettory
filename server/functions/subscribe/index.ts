import { handleSubscribe } from "../../src/handlers.ts";
import { createSupabaseStore } from "../_shared/supabase_store.ts";
import { endpointPolicy, rateLimiter } from "../_shared/limits.ts";
import { serve } from "../_shared/http.ts";

// POST /subscribe, DELETE /subscribe. Deploy with --no-verify-jwt (anonymous PWA clients).
const store = createSupabaseStore();
Deno.serve((req) => serve(req, (r) => handleSubscribe(r, { store, now: Date.now, rateLimiter, endpointPolicy })));
