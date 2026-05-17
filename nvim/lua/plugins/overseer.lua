return {
  "stevearc/overseer.nvim",
  keys = {
    {
      "<leader>r",
      function()
        local overseer = require("overseer")
        local function editor_height()
          local h = vim.o.lines - vim.o.cmdheight
          if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
            h = h - 1
          end
          if vim.o.laststatus >= 2 or (vim.o.laststatus == 1 and #vim.api.nvim_tabpage_list_wins(0) > 1) then
            h = h - 1
          end
          return h
        end

        local function open_float(task)
          if not task or not task.get_bufnr then
            return false
          end
          local bufnr = task:get_bufnr()
          if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
            return false
          end

          local eheight = editor_height()
          local width = math.max(100, math.floor(vim.o.columns * 0.88))
          local height = math.max(24, math.floor(eheight * 0.82))
          width = math.min(width, vim.o.columns - 6)
          height = math.min(height, eheight - 4)
          local row = math.floor((eheight - height) / 2)
          local col = math.floor((vim.o.columns - width) / 2)

          vim.api.nvim_open_win(bufnr, true, {
            relative = "editor",
            row = row,
            col = col,
            width = width,
            height = height,
            border = "rounded",
            style = "minimal",
          })

          return true
        end

        overseer.run_task({}, function(task, err)
          if err then
            vim.notify(err, vim.log.levels.ERROR)
            return
          end
          if task then
            vim.schedule(function()
              if open_float(task) then
                return
              end
              task:subscribe("on_start", function(started_task)
                vim.schedule(function()
                  open_float(started_task)
                end)
              end)
            end)
          end
        end)
      end,
      desc = "Run task and open output",
    },
    { "<leader>R", "<CMD>OverseerToggle<CR>", desc = "Toggle task list" },
  },
  opts = function(_, opts)
    opts = vim.tbl_deep_extend("force", opts or {}, {
      task_list = {
        height = 0.50,
        min_height = 14,
        max_height = { 50, 0.50 },
      },
    })

    local group = vim.api.nvim_create_augroup("OverseerOutputQClose", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "OverseerOutput",
      callback = function(args)
        vim.keymap.set("n", "q", "<CMD>close<CR>", {
          buffer = args.buf,
          silent = true,
          desc = "Close Overseer output",
        })
        vim.keymap.set("t", "q", [[<C-\><C-n><CMD>close<CR>]], {
          buffer = args.buf,
          silent = true,
          desc = "Close Overseer output",
        })
      end,
    })
    return opts
  end,
}
