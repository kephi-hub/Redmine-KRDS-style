# 접속정보 화면에 SSH 버튼·모달 스크립트, 상세 화면 버튼, 목록 위 [접속 기록]
module SshConsole
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      c = context[:controller]
      return '' unless c.is_a?(KeysController) || c.is_a?(SshSessionsController)
      stylesheet_link_tag('ssh_console', plugin: 'vault_ssh') + javascript_include_tag('ssh_console', plugin: 'vault_ssh')
    end

    def view_layouts_base_body_bottom(context = {})
      c = context[:controller]
      return '' unless c.is_a?(KeysController)
      project = c.instance_variable_get(:@project)
      key = c.instance_variable_get(:@key)
      out = ''.html_safe
      if c.action_name == 'show' && key && SshConsole::Target.ssh_key?(key)
        out += context[:hook_caller].render(partial: 'ssh_console/key_buttons', locals: { key: key })
      end
      if c.action_name == 'index' && project && (User.current.allowed_to?(:use_ssh_terminal, project) || User.current.allowed_to?(:use_ssh_terminal_prod, project) || User.current.allowed_to?(:view_ssh_sessions, project))
        out += context[:hook_caller].render(partial: 'ssh_console/sessions_link', locals: { project: project })
      end
      out
    end
  end
end
