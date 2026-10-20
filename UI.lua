-- Building blocks for the Deno Wardrobe window (same as Deno AH): flat blocks, outlined buttons, text boxes, tick boxes.

local ADDON, ns = ...

local C = ns.COLOR

-- A flat fill with a one pixel outline, drawn with plain textures.
function ns.Panel(frame, fill, edge, alpha)
    local bg = frame.denoBg or frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(fill[1], fill[2], fill[3], alpha or 1)
    frame.denoBg = bg

    if not frame.denoEdges then
        local edges = {}
        for i = 1, 4 do edges[i] = frame:CreateTexture(nil, "BORDER") end
        edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(1)
        frame.denoEdges = edges
    end
    ns.Edge(frame, edge or C.line)
end

function ns.Edge(frame, color)
    for _, tex in ipairs(frame.denoEdges) do
        tex:SetColorTexture(color[1], color[2], color[3], 1)
    end
end

function ns.Label(parent, text, size, color)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local file, _, flags = font:GetFont()
    font:SetFont(file, size or 12, flags)
    font:SetText(text or "")
    color = color or C.textDim
    font:SetTextColor(color[1], color[2], color[3])
    font:SetJustifyH("LEFT")
    return font
end

function ns.Heading(parent, text)
    local font = ns.Label(parent, text, 10, C.accent)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", font, "BOTTOMLEFT", 0, -3)
    rule:SetSize(26, 1)
    rule:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
    return font
end

-- A dark button with an outline. SetColor tints it: green when it buys, amber when it waits.
function ns.Button(parent, text, width, height, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    ns.Panel(button, C.accentDim, C.edge)
    button.text = ns.Label(button, text, size or 12, C.text)
    button.text:SetPoint("CENTER")
    button.text:SetJustifyH("CENTER")

    local function Paint(self)
        local color = self.tint
        local fill, edge = C.accentDim, C.edge
        if color then
            fill = { color[1] * 0.30, color[2] * 0.30, color[3] * 0.30 }
            edge = color
        end
        local lift = self.hovered and 0.06 or 0
        self.denoBg:SetColorTexture(fill[1] + lift, fill[2] + lift, fill[3] + lift, 1)
        ns.Edge(self, (self.hovered and not color) and C.hover or edge)
    end

    function button:SetColor(color)
        self.tint = color
        Paint(self)
    end

    button:SetScript("OnEnter", function(self) self.hovered = true Paint(self) end)
    button:SetScript("OnLeave", function(self) self.hovered = false Paint(self) end)
    return button
end

function ns.EditBox(parent, width, height, numeric)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, height)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetJustifyH("RIGHT")
    if numeric then box:SetNumeric(true) end
    ns.Panel(box, C.inset, C.line)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) ns.Edge(self, C.hover) end)
    box:HookScript("OnEditFocusLost", function(self) ns.Edge(self, C.line) end)
    return box
end

-- A flat tick box, big enough to hit.
function ns.CheckBox(parent, text)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(24, 24)

    local well = CreateFrame("Frame", nil, check)
    well:SetSize(16, 16)
    well:SetPoint("CENTER")
    ns.Panel(well, C.inset, C.border)

    local tick = well:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("CENTER")
    tick:SetSize(10, 10)
    tick:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    tick:Hide()

    local setChecked = check.SetChecked
    function check:SetChecked(on)
        setChecked(self, on and true or false)
        tick:SetShown(on and true or false)
    end
    check:SetScript("PostClick", function(self) tick:SetShown(self:GetChecked() and true or false) end)

    check.label = ns.Label(check, text, 12, C.text)
    check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    -- the words count as part of the box: a click on them ticks it too
    check:SetHitRectInsets(0, -260, 0, 0)
    return check
end
