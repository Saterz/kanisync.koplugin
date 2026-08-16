---@meta

---@alias ReadingStatus string
---| "CURRENT" Currently watching/reading
---| "PLANNING"	Planning to watch/read
---| "COMPLETED" Finished watching/reading
---| "DROPPED" Stopped watching/reading before completing
---| "PAUSED" Paused watching/reading
---| "REPEATING" Re-watching/reading

---@alias AniListFuzzyDate { year?: integer, month?: integer, day?: integer }

---@alias KanisyncEntry { id: number, title: string?, format: string?, chapters: integer?, volumes: integer?, start_date: AniListFuzzyDate?, user_list_entry: { id: number?, status: ReadingStatus?, score: number?, progress: integer, progress_volumes: integer, notes: string?, started_at: AniListFuzzyDate?, completed_at: AniListFuzzyDate? } }
