import { handleTime } from "../../src/handlers.ts";
import { createSupabaseStore } from "../_shared/supabase_store.ts";
import { serve } from "../_shared/http.ts";

// GET /time. Deploy with --no-verify-jwt. Touches no data.
const store = createSupabaseStore();
Deno.serve((req) => serve(req, (r) => handleTime(r, { store, now: Date.now })));
