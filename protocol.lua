-- protocol.lua
-- Copie em /home/ nos 3 dispositivos (PC, tablet, drone)

local P = {}

-- Tipos de mensagem
P.MSG_LIST    = "LIST"
P.MSG_ADD     = "ADD"
P.MSG_EDIT    = "EDIT"
P.MSG_REMOVE  = "REMOVE"
P.MSG_GET     = "GET"
P.MSG_MISSION = "MISSION"
P.MSG_OK      = "OK"
P.MSG_ERROR   = "ERROR"
P.MSG_LOG     = "LOG"
P.MSG_REPLY   = "REPLY"

-- Waypoint de retorno no dislocator
P.WAYPOINT_BASE = "base"

return P
