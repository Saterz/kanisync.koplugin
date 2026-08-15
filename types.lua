---@meta

---@alias ReadingStatus string
---| "CURRENT" Currently watching/reading
---| "PLANNING"	Planning to watch/read
---| "COMPLETED" Finished watching/reading
---| "DROPPED" Stopped watching/reading before completing
---| "PAUSED" Paused watching/reading
---| "REPEATING" Re-watching/reading

---@alias KanisyncEntry { id: number, title: string?, user_list_entry: { id: number?, status: ReadingStatus, score: number?, progress: number?, progress_volumes: number?, notes: string? }, fetched_at: number }
