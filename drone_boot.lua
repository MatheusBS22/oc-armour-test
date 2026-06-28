local dr=component.proxy(component.list("drone")())
local function st(s) if dr then dr.setStatusText(tostring(s):sub(1,50)) end end
local i=component.proxy(component.list("internet")())
if not i then st("SEM INET") while true do computer.pullSignal(1) end end
local h=i.request("https://raw.githubusercontent.com/MatheusBS22/oc-armour-test/main/drone.lua")
h.finishConnect()
local c=""
repeat
  local d,e=h.read(512)
  if d then c=c..d end
until not d
h.close()
st("bytes:"..#c)
computer.pullSignal(0.5)
-- Testa sintaxe linha por linha para achar o problema
local fn,err=load(c)
if not fn then
  -- Mostra posição do erro
  st(tostring(err))
  computer.pullSignal(2)
  -- Tenta mostrar a linha problemática
  local linha=tostring(err):match(":(%d+):")
  if linha then
    local n=tonumber(linha)
    local i2=0
    local l=0
    for line in c:gmatch("[^\n]+") do
      l=l+1
      if l>=n-1 and l<=n+1 then
        st("L"..l..":"..line:sub(1,40))
        computer.pullSignal(1.5)
      end
    end
  end
  while true do computer.pullSignal(1) end
end
st("run")
local ok,e2=pcall(fn)
if not ok then st(tostring(e2):sub(1,50)) while true do computer.pullSignal(1) end end
