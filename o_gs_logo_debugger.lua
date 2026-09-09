-- gs_logo_debugger.lua

local function safe(fn) local ok, r = pcall(fn) return ok and r or nil end

local function run_mm(js)
    local mm = safe(function() return panorama.open("CSGOMainMenu") end)
    if not mm then
        client.color_log(255, 80, 80, "[GS] CSGOMainMenu not available — go to MAIN MENU")
        return
    end
    safe(function() mm.loadstring(js)() end)
end

ui.new_button("VISUALS", "Other ESP", "GS: Dump All Panel Types", function()
    run_mm([[
        (function(){
            $.Msg("=== ALL PANEL TYPES ===");
            var types = {};
            var total = 0;
            function walk(p, depth) {
                if (!p || depth > 20) return;
                try {
                    total++;
                    var t = p.paneltype || "null";
                    types[t] = (types[t] || 0) + 1;
                    var n = p.GetChildCount ? p.GetChildCount() : 0;
                    for (var i = 0; i < n; i++) walk(p.GetChild(i), depth + 1);
                } catch(e) {}
            }
            var root = $.GetContextPanel();
            $.Msg("ctx panel id=" + (root ? root.id : "null") + " type=" + (root ? root.paneltype : "null"));
            while (root && root.GetParent && root.GetParent()) root = root.GetParent();
            $.Msg("root id=" + (root ? root.id : "null") + " type=" + (root ? root.paneltype : "null"));
            walk(root, 0);
            $.Msg("Total panels: " + total);
            for (var k in types) $.Msg("  " + k + " x " + types[k]);
            $.Msg("=== END ===");
        })();
    ]])
    client.log("[GS] check console (~)")
end)

ui.new_button("VISUALS", "Other ESP", "GS: Tint ALL Panels (flash)", function()
    run_mm([[
        (function(){
            var count = 0;
            function walk(p, depth) {
                if (!p || depth > 20) return;
                try {
                    if (p.style) {
                        p.style.washColor = "#ff0000";
                        count++;
                    }
                    var n = p.GetChildCount ? p.GetChildCount() : 0;
                    for (var i = 0; i < n; i++) walk(p.GetChild(i), depth + 1);
                } catch(e) {}
            }
            var root = $.GetContextPanel();
            while (root && root.GetParent && root.GetParent()) root = root.GetParent();
            walk(root, 0);
            $.Msg("Tinted " + count + " panels red");
        })();
    ]])
end)

ui.new_button("VISUALS", "Other ESP", "GS: Dump Only IDs (main menu)", function()
    run_mm([[
        (function(){
            $.Msg("=== IDs ===");
            function walk(p, depth) {
                if (!p || depth > 20) return;
                try {
                    if (p.id) $.Msg(new Array(depth+1).join("  ") + p.paneltype + ":" + p.id);
                    var n = p.GetChildCount ? p.GetChildCount() : 0;
                    for (var i = 0; i < n; i++) walk(p.GetChild(i), depth + 1);
                } catch(e) {}
            }
            var root = $.GetContextPanel();
            while (root && root.GetParent && root.GetParent()) root = root.GetParent();
            walk(root, 0);
            $.Msg("=== END ===");
        })();
    ]])
    client.log("[GS] check console")
end)
