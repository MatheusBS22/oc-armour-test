-- protocol.lua
-- Constantes compartilhadas entre server, tablet e drone.
-- Copie este arquivo nos 3 computadores no mesmo caminho: /home/protocol.lua

local P = {}

-- ----------------------------------------------------------------
-- Portas de comunicação (cada canal tem um propósito)
-- ----------------------------------------------------------------
P.PORT_SERVER  = 5550  -- tablet  → server  (requisições CRUD)
P.PORT_REPLY   = 5551  -- server  → tablet  (respostas)
P.PORT_DRONE   = 5552  -- tablet  → drone   (missões)
P.PORT_STATUS  = 5553  -- drone   → tablet  (status/log)

-- ----------------------------------------------------------------
-- Tipos de mensagem tablet → server
-- ----------------------------------------------------------------
P.MSG_LIST    = "LIST"    -- pede lista completa de armaduras
P.MSG_ADD     = "ADD"     -- adiciona armadura
P.MSG_EDIT    = "EDIT"    -- edita armadura existente
P.MSG_REMOVE  = "REMOVE"  -- remove armadura pelo id
P.MSG_GET     = "GET"     -- pede uma armadura pelo id

-- ----------------------------------------------------------------
-- Tipos de mensagem tablet → drone
-- ----------------------------------------------------------------
P.MSG_MISSION = "MISSION" -- envia missão: {x, y, z, armor_id}

-- ----------------------------------------------------------------
-- Tipos de mensagem drone → tablet
-- ----------------------------------------------------------------
P.MSG_OK      = "OK"
P.MSG_ERROR   = "ERROR"
P.MSG_LOG     = "LOG"     -- mensagem de status durante a missão

-- ----------------------------------------------------------------
-- Nome do waypoint de retorno no DislocatorAdvanced
-- O drone vai procurar um destino com esse nome exato após a missão
-- ----------------------------------------------------------------
P.WAYPOINT_BASE = "base"

return P
