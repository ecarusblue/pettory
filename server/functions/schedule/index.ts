import { handleSchedule } from "../../src/handlers.ts";
import { createSupabaseStore } from "../_shared/supabase_store.ts";
import { rateLimiter } from "../_shared/limits.ts";
import { serve } from "../_shared/http.ts";

// PUT /schedule. Deploy with --no-verify-jwt.
const store = createSupabaseStore();
Deno.serve((req) => serve(req, (r) => handleSchedule(r, { store, now: Date.now, rateLimiter })));
