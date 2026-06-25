-- protocol.lua
-- Constantes compartilhadas entre server, tablet e drone.
-- Copie este arquivo em /home/ nos 3 computadores.
--
-- LINKED CARD: componente "tunnel" no Lua
-- Não usa portas — o tipo da mensagem identifica o destinatário.
-- Evento recebido: modem_message (mesmo nome do modem normal)

local P = {}

-- ----------------------------------------------------------------
-- Tipos de mensagem tablet → server
-- ----------------------------------------------------------------
P.MSG_LIST    = "LIST"
P.MSG_ADD     = "ADD"
P.MSG_EDIT    = "EDIT"
P.MSG_REMOVE  = "REMOVE"
P.MSG_GET     = "GET"

-- ----------------------------------------------------------------
-- Tipos de mensagem tablet → drone
-- ----------------------------------------------------------------
P.MSG_MISSION = "MISSION"

-- ----------------------------------------------------------------
-- Tipos de mensagem drone/server → tablet
-- ----------------------------------------------------------------
P.MSG_OK      = "OK"
P.MSG_ERROR   = "ERROR"
P.MSG_LOG     = "LOG"
P.MSG_REPLY   = "REPLY"  -- resposta do server ao tablet

-- ----------------------------------------------------------------
-- Nome do waypoint de retorno no DislocatorAdvanced
-- ----------------------------------------------------------------
P.WAYPOINT_BASE = "base"

return P
