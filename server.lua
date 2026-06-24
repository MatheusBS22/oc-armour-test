-- server.lua
-- Roda no PC fixo em base.
-- Guarda a lista de armaduras em /home/armors.json e responde
-- requisições do tablet via modem.
--
-- Para iniciar: server
-- Para rodar automaticamente ao ligar, salve como /home/autorun.lua

local component  = require("component")
local event      = require("event")
local serial     = require("serialization")
local filesystem = require("filesystem")
local P          = require("protocol")

-- ----------------------------------------------------------------
-- Verifica componentes
-- ----------------------------------------------------------------
if not component.isAvailable("modem") then
    error("Modem não encontrado no PC servidor!")
end

local modem = component.modem
local SAVE_PATH = "/home/armors.json"

-- ----------------------------------------------------------------
-- Persistência — carrega / salva armaduras em JSON
-- ----------------------------------------------------------------

-- Estrutura de cada armadura:
-- {
--   id      = number,   -- identificador único (1, 2, 3...)
--   name    = string,   -- nome legível ex: "Armadura Draconica"
--   x       = number,
--   y       = number,
--   z       = number,
-- }

local function load()
    if not filesystem.exists(SAVE_PATH) then
        return {}
    end
    local f = io.open(SAVE_PATH, "r")
    local raw = f:read("*a")
    f:close()
    return serial.unserialize(raw) or {}
end

local function save(armors)
    local f = io.open(SAVE_PATH, "w")
    f:write(serial.serialize(armors))
    f:close()
end

-- Gera o próximo id disponível
local function nextId(armors)
    local max = 0
    for _, a in ipairs(armors) do
        if a.id > max then max = a.id end
    end
    return max + 1
end

-- Acha índice na lista pelo id
local function findIndex(armors, id)
    for i, a in ipairs(armors) do
        if a.id == id then return i end
    end
    return nil
end

-- ----------------------------------------------------------------
-- Handlers de cada tipo de mensagem
-- ----------------------------------------------------------------

local armors = load()

local handlers = {}

-- LIST → devolve a lista completa
handlers[P.MSG_LIST] = function(data)
    return { ok = true, armors = armors }
end

-- GET {id} → devolve uma armadura
handlers[P.MSG_GET] = function(data)
    local idx = findIndex(armors, data.id)
    if not idx then
        return { ok = false, error = "Armadura id=" .. tostring(data.id) .. " não encontrada" }
    end
    return { ok = true, armor = armors[idx] }
end

-- ADD {name, x, y, z} → adiciona e devolve o id gerado
handlers[P.MSG_ADD] = function(data)
    if not data.name or not data.x or not data.y or not data.z then
        return { ok = false, error = "Campos obrigatórios: name, x, y, z" }
    end
    local armor = {
        id   = nextId(armors),
        name = tostring(data.name),
        x    = tonumber(data.x),
        y    = tonumber(data.y),
        z    = tonumber(data.z),
    }
    table.insert(armors, armor)
    save(armors)
    return { ok = true, armor = armor }
end

-- EDIT {id, name?, x?, y?, z?} → edita campos fornecidos
handlers[P.MSG_EDIT] = function(data)
    local idx = findIndex(armors, data.id)
    if not idx then
        return { ok = false, error = "Armadura id=" .. tostring(data.id) .. " não encontrada" }
    end
    local a = armors[idx]
    if data.name then a.name = tostring(data.name) end
    if data.x    then a.x    = tonumber(data.x)    end
    if data.y    then a.y    = tonumber(data.y)     end
    if data.z    then a.z    = tonumber(data.z)     end
    save(armors)
    return { ok = true, armor = a }
end

-- REMOVE {id} → remove da lista
handlers[P.MSG_REMOVE] = function(data)
    local idx = findIndex(armors, data.id)
    if not idx then
        return { ok = false, error = "Armadura id=" .. tostring(data.id) .. " não encontrada" }
    end
    local removed = armors[idx]
    table.remove(armors, idx)
    save(armors)
    return { ok = true, armor = removed }
end

-- ----------------------------------------------------------------
-- Loop principal
-- ----------------------------------------------------------------

modem.open(P.PORT_SERVER)
print("╔══════════════════════════════╗")
print("║   SERVIDOR DE ARMADURAS OC   ║")
print("╚══════════════════════════════╝")
print("Aguardando requisições na porta " .. P.PORT_SERVER .. "...")
print("Armaduras carregadas: " .. #armors)
print("")

while true do
    -- _, endLocal, endRemoto, porta, distancia, mensagem
    local _, _, sender, port, _, raw = event.pull("modem_message")

    if port == P.PORT_SERVER then
        local ok, msg = pcall(serial.unserialize, raw)

        if not ok or type(msg) ~= "table" or not msg.type then
            -- mensagem malformada — ignora silenciosamente
            print("[!] Mensagem inválida de " .. tostring(sender))
        else
            local handler = handlers[msg.type]
            local response

            if not handler then
                response = { ok = false, error = "Tipo desconhecido: " .. msg.type }
            else
                local success, result = pcall(handler, msg.data or {})
                if success then
                    response = result
                else
                    response = { ok = false, error = tostring(result) }
                end
            end

            print("[" .. msg.type .. "] de " .. sender:sub(1, 8) ..
                  " → " .. (response.ok and "OK" or "ERRO: " .. (response.error or "?")))

            -- Responde ao tablet
            modem.send(sender, P.PORT_REPLY, serial.serialize(response))
        end
    end
end
