local Fields = {}

Fields.media = [[
fragment MediaSummary on Media {
  id
  type
  isAdult
  title { userPreferred romaji english native }
  format
  status
  chapters
  volumes
  episodes
  startDate { year month day }
  coverImage { medium large }
  siteUrl
}
]]

Fields.list_entry = [[
fragment ListEntryFields on MediaList {
  id
  mediaId
  status
  score
  progress
  progressVolumes
  repeat
  notes
  startedAt { year month day }
  completedAt { year month day }
  createdAt
  updatedAt
}
]]

return Fields
