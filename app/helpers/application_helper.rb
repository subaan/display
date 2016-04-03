module ApplicationHelper
  SITE_ICONS = {:organization     => 'sitemap',
                :home             => 'home',
                :dashboard        => 'dashboard',
                :service          => 'cog',
                :catalog          => 'tags',
                :cloud            => 'cloud',
                :assembly         => 'cogs',
                :settings         => 'sliders',
                :user             => 'user',
                :manages_access   => 'key',
                :org_scope        => 'sitemap',
                :design           => 'puzzle-piece',
                :transition       => 'play-circle-o',
                :operations       => 'signal',
                :cloud_services   => 'cog',
                :cloud_compliance => 'briefcase',
                :cloud_support    => 'medkit',
                :cost             => 'money',
                :export           => 'download',
                :import           => 'upload'}

  GENERAL_SITE_LINKS = [{:label => 'Get help',         :icon => 'comments',  :url => Settings.support_chat_url},
                        {:label => 'Report a problem', :icon => 'bug',       :url => Settings.report_problem_url},
                        {:label => 'Feedback',         :icon => 'comment-o', :url => Settings.feedback_url},
                        {:label => 'Documentation',    :icon => 'book',      :url => Settings.help_url},
                        {:label => 'Release notes',    :icon => 'rss',       :url => Settings.news_url}]

  def omniauth_services
    omniauth = Settings.omniauth
    return '' unless omniauth
    services = omniauth.keys.sort.inject([]) {|s, p| s << link_to(p, "/auth/#{p}", :title => p.capitalize)}
    return raw(services.join(' '))
  end

  def title(page_title)
    content_for(:title) { content_tag(:div, page_title.html_safe, :id => "title_text") }
    content_for(:title_clean) {"#{page_title.gsub( /<.+?>/, '')} - OneOps"}
  end

  def organization_home
    current_user.organization_id? ? content_tag(:div, link_to(current_user.organization.name, organization_path).html_safe, :class => "title_text" ) : ''
  end

  def app_nav(items)
    html = '<ul>'
    items.each do |item|
      selected = item[:selected] ? 'selected' : ''
      label = item[:label]
      icon = item[:icon]
      caption = icon.blank? ? label : icon(icon, label)
      html << content_tag(:li, (item[:link] ? link_to(caption, item[:link]) : caption), :class => "#{selected}")
    end
    html << '</ul>'
    content_for(:app_nav) { html.html_safe }
  end

  def organization_title
    content_for(:title) { organization_home }
    content_for(:title_clean) {"#{current_user.organization_id? ? current_user.organization.name : ''} | OneOps" }
  end

  def root_page_header(selected = nil)
    return unless user_signed_in?
    content_for(:title) { content_tag(:div, link_to(current_user.username, root_path).html_safe, :class => 'title_text' ) }
    content_for(:title_clean) {'OneOps' }

    menu_items = [{:label => 'profile',   :link => account_profile_path}]
    if selected
      selected_item = menu_items.detect { |i| i[:label] == selected }
      selected_item[:selected] = true if selected_item
    end
    app_nav(menu_items)
  end

  def organization_page_header(selected = nil)
    return unless user_signed_in? && current_user.organization_id.present?

    organization_title
    menu_items = []
    menu_items << {:label => 'services', :icon => site_icon(:service), :link => services_path} if current_user.organization.services
    menu_items << {:label => 'catalogs', :icon => site_icon(:catalog), :link => catalogs_path} if current_user.organization.catalogs

    if current_user.organization.assemblies
      menu_items << {:label => 'clouds', :icon => site_icon(:cloud), :link => clouds_path}
      menu_items << {:label => 'assemblies', :icon => site_icon(:assembly), :link => assemblies_path}
    end

    menu_items << {:icon => site_icon(:settings), :link => edit_organization_path, :selected => selected == 'settings'}

    if selected
      selected_item = menu_items.detect { |i| i[:label] == selected}
      selected_item[:selected] = true if selected_item
    end
    app_nav(menu_items)
  end

  def assembly_title(assembly)
    content = organization_home
    content << content_tag(:div, ' / ', :class => 'title_text')
    content << content_tag(:div, link_to('assemblies', assemblies_path).html_safe, :class => 'title_text')
    content << content_tag(:div, ' / ', :class => 'title_text')
    content << content_tag(:div, link_to(assembly.ciName, assembly_path(assembly)).html_safe, :class => 'title_text')
    content_for(:title) { content.html_safe }
    content_for(:title_clean) {  "#{assembly.ciName} - #{current_user.organization.name} | OneOps" }
  end

  def assembly_page_header(assembly, selected = nil)
    assembly_title(assembly)

    ci = [@component, @platform, @environment].find {|c| c && c.persisted?}

    dto_links = [{:label => 'design',     :icon => site_icon(:design),     :url => assembly_design_path(assembly)},
                 {:label => 'transition', :icon => site_icon(:transition), :url => assembly_transition_path(assembly)},
                 {:label => 'operations', :icon => site_icon(:operations), :url => assembly_operations_path(assembly)}]

    html = '<ul>'
    if ci
      %w(design transition operations).each do |area|
        html << "<li class='#{area} #{'selected' if area == selected}'>"
        html << link_to(icon(site_icon(area.to_sym), area),
                        counterparts_lookup_path(:ci => ci.attributes.slice(:ciId, :nsPath, :ciClassName, :ciName),
                                                 :dto_area => selected),
                        :remote       => true,
                        :class        => 'dropdown-toggle',
                        'data-toggle' => 'dropdown')
        html << '<ul class="dropdown-menu"><li style="text-align:center"><a href="/"><i class="fa-spinner fa-spin"></i></a></li></ul>'
        html << '</li>'
      end
    else
      dto_links.each do |item|
        label = item[:label]
        html << content_tag(:li, link_to(icon(item[:icon], label), item[:url]), :class => label == selected ? 'selected' : '')
      end
    end
    html << '</ul>'
    content_for(:app_nav, html.html_safe)

    begin
      assembly_nav(assembly, ci, dto_links, selected)
    rescue Exception => e
      Rails.logger.warn "Failed to generate assembly nav: #{e}.\nAssembly: #{assembly.inspect}\nCI: #{ci.inspect if ci}"
    end
  end

  def assembly_nav(assembly, ci, dto_links, current_dto)
    assembly_nav = %(<li class="title">#{link_to(icon(site_icon(:assembly), "&nbsp;#{assembly_nav_name_label(assembly.ciName)}"), assembly_path(assembly))}</li>)
    assembly_nav << %(<li class="divider small"></li>)
    if ci
      ci_class_name = ci.ciClassName
      dto_links.each do |l|
        no_more = false
        dto_area = l[:label]
        assembly_nav << %(<li class="major #{'highlight' if dto_area == current_dto}">#{link_to(icon(site_icon(dto_area), dto_area), l[:url])}</li>)
        if ci_class_name == 'manifest.Environment'
          if dto_area == 'design'
            no_more = true
          elsif dto_area != current_dto
            assembly_nav << %(<li class="indent">#{link_to(icon("arrow-circle-#{current_dto == 'operations' ? 'left' : 'right'}", "#{assembly_nav_name_label(ci.ciName)} environment"), path_to_ci(ci, dto_area))}</li>)
          end
        elsif ci_class_name.end_with?('.Platform')
          unless current_dto == 'design'
            if dto_area == 'design'
              assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-left', "#{assembly_nav_name_label(ci.ciName)} platform"), path_to_ci(ci, dto_area))}</li>)
            else
              assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-up', "#{assembly_nav_name_label(@environment.ciName)} environment"), path_to_ci(@environment, dto_area))}</li>) if @environment
              assembly_nav << %(<li class="indent">#{link_to(icon("arrow-circle-#{current_dto == 'operations' ? 'left' : 'right'}", "#{assembly_nav_platform_label(ci)} platform"), path_to_ci(ci, dto_area))}</li>) unless dto_area == current_dto
            end
          end
        else
          if current_dto == 'design'
            assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-up', "#{assembly_nav_name_label(@platform.ciName)} platform"), path_to_ci(@platform, dto_area))}</li>) if @platform && dto_area == 'design'
          else
            if dto_area == 'design'
              assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-up', "#{assembly_nav_name_label(@platform.ciName)} platform"), path_to_ci(@platform, dto_area))}</li>) if @platform
              assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-left', "#{assembly_nav_name_label(ci.ciName)} component"), path_to_ci(ci, dto_area))}</li>)
            else
              assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-up', "#{assembly_nav_name_label(@environment.ciName)} environment"), path_to_ci(@environment, dto_area))}</li>) if @environment
              assembly_nav << %(<li class="indent">#{link_to(icon('arrow-circle-up', "#{assembly_nav_platform_label(@platform)} platform"), path_to_ci(@platform, dto_area))}</li>) if @platform
              assembly_nav << %(<li class="indent">#{link_to(icon("arrow-circle-#{current_dto == 'operations' ? 'left' : 'right'}", "#{assembly_nav_name_label(ci.ciName)} component"), path_to_ci(ci, dto_area))}</li>) unless dto_area == current_dto
            end
          end
        end
        unless no_more
          more_link = link_to(icon('', 'more...'),
                              counterparts_lookup_path(:ci => ci.attributes.slice(:ciId, :nsPath, :ciClassName, :ciName), :dto_area => current_dto),
                              :remote => true)
          assembly_nav << %(<li class='indent minor #{dto_area} more'>#{more_link}</li>)
        end
      end
    else
      dto_links.each do |l|
        dto_area = l[:label]
        assembly_nav << %(<li class="#{'highlight' if dto_area == current_dto}">#{link_to(icon(site_icon(dto_area), dto_area), l[:url])}</li>)
      end
    end

    content_for(:assembly_nav, raw(assembly_nav))
  end

  def assembly_nav_platform_label(platform)
    "#{assembly_nav_name_label(platform.ciName)} <small class=\"muted\">ver. #{platform.ciAttributes.major_version}</small>"
  end

  def assembly_nav_name_label(name)
    "<span class='name'>#{name}</span>"
  end

  def app_subnav(items)
      html = '<ul>'
      items.each do |item|
        selected = item[:selected] ? 'selected' : ''
        html << '<li>'
        if item[:link]
          html << link_to(item[:label], item[:link], :class => selected)
        else
          html << link_to_function(item[:label], item[:function], :class => selected)
        end
        html << '</li>'
      end
      html << '</ul>'
      content_for(:app_subnav) { html.html_safe }
  end

  def breadcrumb(items)
      html = '<ul class="rounded">'
      items.each do |item|
        html << '<li>'
        block = ''
        block << content_tag(:div, image_tag(item[:icon]), :class => 'breadcrumb_image') if item[:icon]
        block << content_tag(:div, sanitize(item[:kind]), :class => 'item_kind') if item[:kind]
        block << content_tag(:div, sanitize(item[:label]), :class => 'item_label')
        html << content_tag(:div, (item[:link] ? link_to(sanitize(block), item[:link]) : block.html_safe), :class => 'breadcrumb_text')
        html << content_tag(:div, icon('angle-right'), :class => 'breadcrumb_separator_text')
        html << '</li>'
      end
      html << '</ul>'
      content_for(:breadcrumb) { html.html_safe }
  end

  def page_title(options)
    html = ''
    page_icon = options[:page_icon]
    page_kind = options[:page_kind]
    icon_lookup = page_icon.presence || page_kind
    icon_name = icon_lookup.present? && (site_icon!(icon_lookup.downcase) || site_icon!(icon_lookup.downcase.singularize))
    if icon_name
      html << icon(icon_name) if icon_name
    else
      html = image_tag(page_icon)
    end

    fav   = ''
    ci_id = params[:id]
    if ci_id.present? && /(\/assemblies\/)|(\/clouds\/)/ =~ request.url
      fav = link_to_function(content_tag(:i, '', :class => "fa fa-bookmark#{'-o' unless current_user.favorite(ci_id.to_i)}", :title => 'Mark/remove favorite'),
                             "toggleFavorite(this, '#{ci_id }')",
                             :class => 'favorite')

    end
    block = ''
    block << content_tag(:span, sanitize(page_kind), :class => 'page_kind') if page_kind
    doc_link = options[:doc_link]
    if options[:page_label]
      block << content_tag(:span, raw("#{sanitize(options[:page_label])}"), :class => 'page_label')
      block << fav
      block << doc_link if doc_link.present?
    end
    block << content_tag(:span, sanitize(options[:page_sublabel]), :class => 'page_sublabel') if options[:page_sublabel]
    html << content_tag(:div, raw(block), :id => 'page_title_text')

    html << content_tag(:ul, raw(options[:page_options].join(' ')), :id => 'page_title_options') if options[:page_options]
    content_for(:page_title, raw(html))
  end

  def page_info(info)
    content_for(:page_info, sanitize(info || ''))
  end

  def error_messages_for(model)
    html = ''
    if model.errors.any?
      html << '<div class="alert alert-danger error-messages">Please correct the following errors:'
      html << '<ul>'
      model.errors.full_messages.each {|m| html << "<li>#{html_escape(m)}</li>"}
      html << '</ul>'
      html << '</div>'
      html << '<script>$j(".error-messages")[0].scrollIntoView(false)</script>'
    end
    raw(html)
  end

  def note(options)
     header = content_tag(:div, options[:severity], :class => 'header')
     text = content_tag(:div, options[:text], :class => 'text')
     content_tag :div, header + text, :class => "note #{options[:severity].downcase}"
  end

  def section_panel(title, options = {}, &block)
    options.reverse_merge!(:title => title, :menu => nil)
    defaults = {:width => 'double', :position => 'left'}
    options = defaults.merge(options)
    options.merge!(:body => capture(&block)) if block_given?
    raw(%(#{render(:partial => 'base/shared/section_panel', :locals => options)}))
  end

  def list_simple(collection, options = {}, &block)
    options[:toolbar] = nil if collection.blank?
    options.reverse_merge!({:item_partial => 'base/shared/list_simple_item', :toolbar => {:sort_by => [], :filter_by => %w(id)}})
    render(:partial => 'base/shared/list', :locals => {:list_content => ListItemBuilder.build_list_item_content(collection, self, options, &block), :options => options})
  end

  def list(collection, options = {}, &block)
    options[:toolbar] = nil if collection.blank?
    options.reverse_merge!({:item_partial => 'base/shared/list_item', :toolbar => {:sort_by => [], :filter_by => %w(id)}})
    render(:partial => 'base/shared/list', :locals => {:list_content => ListItemBuilder.build_list_item_content(collection, self, options, &block), :options => options})
  end

  def ci_list(ci_collection, options = {}, &block)
    options[:toolbar] = nil if ci_collection.blank?
    options.reverse_merge!({:item_partial => 'base/shared/ci_list_item', :toolbar => {:sort_by => [%w(Id ciId), %w(Name ciName), %w(Created created)], :filter_by => %w(ciName)}})
    render(:partial => 'base/shared/list', :locals => {:list_content => ListItemBuilder.build_list_item_content(ci_collection, self, options, &block), :options => options})
  end

  def relation_list(relation_collection, options = {}, &block)
    options.reverse_merge!({:item_partial => 'base/shared/relation_list_item', :class => 'list-relation', :toolbar => nil})
    render(:partial => 'base/shared/list', :locals => {:list_content => ListItemBuilder.build_list_item_content(relation_collection, self, options, &block), :options => options})
  end

  def release_list(release_collection, options = {}, &block)
    options[:toolbar] = nil if release_collection.blank? && options[:paginate].blank?
    options.reverse_merge!({:class   => 'list-release',
                            :toolbar => {:list_name => 'release_list',
                                         :sort_by   => [['Release ID', 'releaseId'], %w(Created created), %w(User createdBy)],
                                         :filter_by => %w(releaseId description createdBy)}})
    render(:partial => 'base/shared/list', :locals => {:list_content => render_release_list_content(release_collection, options, &block), :options => options})
  end

  def render_release_list_content(release_collection, options = {}, &block)
    raw ListItemBuilder.build_list_item_content(release_collection, self, options.merge(:item_partial => 'base/shared/release_list_item'), &block)
  end

  def deployment_list(deployment_collection, options = {}, &block)
    options[:toolbar] = nil if deployment_collection.blank? && options[:paginate].blank?
    options.reverse_merge!({:class   => 'list-deployment',
                            :toolbar => {:list_name => 'deployment_list',
                                         :sort_by   => [['Deployment ID', 'deploymentId'], %w(Created created), %w(User createdBy), ['Deployment State', 'deploymentState']],
                                         :filter_by => %w(deploymentId createdBy deploymentState)}})
    render(:partial => 'base/shared/list',
           :locals  => {:list_content => render_deployment_list_content(deployment_collection, options, &block), :options => options})
  end

  def render_deployment_list_content(deployment_collection, options = {}, &block)
    raw ListItemBuilder.build_list_item_content(deployment_collection, self, options.merge(:item_partial => 'base/shared/deployment_list_item'), &block)
  end

  def notification_list(notification_collection, options = {}, &block)
    if notification_collection
      options[:toolbar] = nil if notification_collection.blank? && options[:paginate].blank?
      options.reverse_merge!({:class   => 'list-notification',
                              :toolbar => {:sort_by   => [%w(Time time), %w(Source source), %w(Severity severity)],
                                           :filter_by => %w(date severity source subject text)}})
      render(:partial => 'base/shared/list',
             :locals => {:list_content => render_notification_list_content(notification_collection, options, &block), :options => options})
    else
      falied_loading_indicator('Failed to load notification_collection, please try again later.</p>')
    end
  end

  def render_notification_list_content(notification_collection, options = {}, &block)
    raw ListItemBuilder.build_list_item_content(notification_collection, self, options.merge(:item_partial => 'base/shared/notification_list_item'), &block)
  end

  def notification_callback(data, full_url = false)
    nspath = data['nsPath']
    source = data['source']
    case source
      when 'deployment'
        root, organization, assembly, environment, scope = nspath.split('/')
        if full_url
          link_to(nspath, assembly_transition_environment_url(:only_path   => false,
                                                              :org_name    => organization,
                                                              :assembly_id => assembly,
                                                              :id          => environment))
        else
          link_to(nspath, assembly_transition_environment_path(:org_name    => organization,
                                                               :assembly_id => assembly,
                                                               :id          => environment))
        end
      when 'procedure', 'opamp', 'ops'
        if full_url
          link_to("#{nspath}/#{data['cmsId']}", redirect_ci_url(:only_path => false, :id => data['cmsId']))
        else
          link_to("#{nspath}/#{data['cmsId']}", redirect_ci_path(:id => data['cmsId']))
        end
      else
        if full_url
          link_to(nspath, redirect_ns_url(:only_path => false, :params => {:path => nspath}))
        else
          link_to(nspath, redirect_ns_path(:params => {:path => nspath}))
        end
    end
  end

  class ListItemBuilder < Hash
    attr_accessor :item

    def initialize(item, template, options = {})
      @item     = item
      @template = template
      @options  = options
    end

    def method_missing(symbol, *args, &block)
      self[symbol] = block_given? ? @template.capture(@item, &block) : args[0]
    end

    def self.build_list_item_content(item_collection, template, options, group = nil, &block)
      item_collection.inject('') do |content, item|
        list_item_builder = ListItemBuilder.new(item, template, options)
        template.capture list_item_builder, item, &block if block_given?
        content << template.render(:partial => options[:item_partial], :locals => {:item => item, :group => group, :builder => list_item_builder, :collapse => options[:collapse], :multi_select => options[:menu].present?})
      end
    end
  end

  def grouped_ci_list(groups, options = {}, &block)
    options[:toolbar] = nil if groups.blank?
    options.reverse_merge!({:item_partial => 'base/shared/ci_list_item', :toolbar => {:filter_by => %w(ciName)}, :collapse => false})

    list_content = groups.inject('') do |content, group|
      list_group_builder = ListGroupBuilder.new(group, self, options)
      capture list_group_builder, group, &block
      content << render(:partial => 'base/shared/list_group', :locals => {:group => group, :builder => list_group_builder})
    end

    render(:partial => 'base/shared/list', :locals => {:list_content => list_content, :options => options})
  end

  def grouped_list(groups, options = {}, &block)
    options[:toolbar] = nil if groups.blank?
    options.reverse_merge!({:item_partial => 'base/shared/list_item', :toolbar => {:sort_by => [], :filter_by => %w(id)}, :collapse => false})

    list_content = groups.inject('') do |content, group|
      list_group_builder = ListGroupBuilder.new(group, self, options)
      capture list_group_builder, group, &block
      content << render(:partial => 'base/shared/list_group', :locals => {:group => group, :builder => list_group_builder})
    end

    render(:partial => 'base/shared/list', :locals => {:list_content => list_content, :options => options})
  end

  class ListGroupBuilder < ListItemBuilder
    def items(item_collection, &block)
      self[:group_content] = self.class.build_list_item_content(item_collection, @template, @options, @item, &block)
    end
  end

  def list_paginate_update(list_id, data, template)
    info    = data.info
    content = escape_javascript(render(template))
    raw("list_paginate_update($j('##{list_id}'), \"#{content}\", #{info[:total] || 0}, #{info[:offset] || 0}, #{data.size || 0})")
  end

  def link_confirm_busy(link_text, options)
    modal_id = "modal_#{random_dom_id}"
    dialog_options = options.extract!(:confirm, :busy, :url, :method, :remote, :with, :comment, :body).merge(:modal_id => modal_id)
    link_to_function(link_text, %(render_modal("#{modal_id}", "#{escape_javascript(render('base/shared/confirm_busy_block', dialog_options))}")), options)
  end

  def link_busy(link_text, options)
    call_options = options.extract!(:with, :url, :method)
    #call = remote_function(:url => call_options[:url], :method => call_options[:method].presence || :get, :with => call_options[:with])
    call = %($j.ajax("#{call_options[:url]}", {type: "#{(call_options[:method].presence || :get).to_s.upcase}", data: #{call_options[:with] || "''"} + "&authenticity_token=" + encodeURIComponent($j("meta[name=csrf-token]").attr("content"))}))

    message = options[:message].presence || options[:busy]
    link_to_function(link_text, %(show_busy(#{"'#{escape_javascript(message)}'" if message.present?}); #{call}), options)
  end

  def truncate(text, length = 30, truncate_string = '...')
    if text
      l = length - truncate_string.length
      (text.length > length ? text[0...l] + truncate_string : text).to_s
    end
  end

  def action_to_label(action)
    case action
    when 'add'
      'label-success'
    when 'update'
      'label-warning'
    when 'replace'
      'label-success'
    when 'delete'
      'label-important'
    else
      ''
    end
  end

  def action_to_text(action)
    case action
    when 'add'
      'text-success'
    when 'update'
      'text-warning'
    when 'replace'
      'text-success'
    when 'delete'
      'text-error'
    else
      ''
    end
  end

  def action_to_background(action)
    case action
    when 'add'
      'success'
    when 'update'
      'warning'
    when 'replace'
      'success'
    when 'delete'
      'error'
    else
      ''
    end
  end

  def state_to_text(state)
    case state
    when 'enabled'
      'text-success'
    when 'pending'
      'text-info'
    when 'open'
      'text-info'
    when 'active'
      'text-success'
    when 'paused'
      'text-warning'
    when 'complete'
      'text-success'
    when 'closed'
      ''
    when 'inprogress'
      'text-info'
    when 'pending'
      ''
    when 'failed'
      'text-error'
    when 'canceled'
      'text-error'
    when 'inactive'
      'text-error'
    else
      ''
    end
  end

  def state_to_label(state)
    case state
    when 'enabled'
      'label-success'
    when 'stale'
      'label-info'
    when 'open'
      'label-info'
    when 'active'
      'label-info'
    when 'paused'
      'label-warning'
    when 'pausing'
      'label-warning'
    when 'complete'
      'label-success'
    when 'closed'
      'label-success'
    when 'inprogress'
      'label-info'
    when 'pending'
      ''
    when 'failed'
      'label-important'
    when 'canceled'
      'label-important'
    when 'inactive'
      'label-important'
    when 'disabled'
      'label-important'
      when 'replace'
        'label-notice'
    else
      ''
    end
  end

  def health_to_label(state)
    case state
    when 'good'
      'label-success'
    when 'notify'
      'label-info'
    when 'unhealthy'
      'label-important'
    when 'overutilized'
      'label-warning'
    when 'underutilized'
      'label-info'
    else
      ''
    end
  end

  def ops_state_legend
    [{:name => 'good',          :color => '#468847'},
     {:name => 'notify', :color => '#3a87ad'},
     {:name => 'unhealthy', :color => '#b94a48'},
     {:name => 'overutilized', :color => '#f89406'},
     {:name => 'underutilized', :color => '#800080'},
     {:name => 'unknown', :color => '#999999'}]
  end

  def cloud_admin_status_label(status)
    case status
      when 'active'
        'label-success'
      when 'inert'
        'label-info'
      when 'offline'
        'label-warning'
      else
        ''
    end
  end

  def cloud_admin_status_button(status)
    case status
      when 'active'
        'btn-success'
      when 'inert'
        'btn-info'
      when 'offline'
        'btn-warning'
      else
        ''
    end
  end

  def cloud_admin_status_icon(status)
    case status
      when 'active'
        'cloud-upload'
      when 'inert'
        'cloud'
      when 'offline'
        'cloud-download'
      else
        'cloud'
    end
  end

  def highlight(value, label_class = '', options = {})
    content_tag(:span, value, :class => "highlight #{label_class}")
  end

  def marker(value, label_class = '', options = {})
    toggle = options['data-toggle']
    marker = content_tag(:span, raw("#{value}#{" #{icon('caret-down')}" if toggle}"), :class => "label label-marker #{label_class}")
    id = random_dom_id
    result = content_tag(:div, marker.html_safe, options.merge(:class => 'marker', :id => id))
    result += javascript_tag(%($j("##{id}").#{toggle}())) if toggle
    result
  end

  def count_marker(count, label_class = '', options = {})
    content_tag(:span, count, options.merge(:class => "label label-count #{label_class}"))
  end

  def status_marker(name, value, label_class = '', options = {})
    toggle = options['data-toggle']
    marker = content_tag(:span, name, :class => "label label-marker-name #{options.delete(:name_class)}")
    marker << content_tag(:span, raw("#{value}#{" #{icon('caret-down')}" if toggle}"), :class => "label label-marker-value #{label_class}")
    id = random_dom_id
    result = content_tag(:div, marker.html_safe, options.merge(:class => 'marker', :id => id))
    result += javascript_tag(%($j("##{id}").#{toggle}())) if toggle
    result
  end

  def instance_marker(platform_clouds, target)
    clouds = platform_clouds["#{target.ciName}/#{target.ciAttributes.major_version}"]
    return '' unless clouds.present?
    clouds = clouds.values
    total = 0
    content = clouds.sort_by {|info| info[:consumes].toCi.ciName}.inject('') do |a, info|
      count  = info[:instances]
      cloud  = info[:consumes]
      status = cloud.relationAttributes.adminstatus
      total += count
      a + "#{cloud.toCi.ciName} - <strong class='#{state_to_text(status)}'>#{count}</strong><br>"
    end
    status_marker('instances', total, 'label-info', total > 0 ? {'data-toggle' => 'popover', 'data-html' => true, 'data-title' => 'Instances By Cloud', 'data-content' => content, 'data-trigger' => 'hover', 'data-placement' => 'top'} : {})
  end

  def icon(name, text = '', icon_class = '')
    icon_html = content_tag(:i, '', :class => "fa fa-#{name} #{icon_class}")
    raw("#{icon_html}#{" #{text}" if text.present?}")
  end

  def loading_indicator(message = 'Loading...')
    icon('spinner', message, 'fa-spin')
  end

  def falied_loading_indicator(message = 'Failed to load')
    raw(%(<p class="text-error">#{icon('exclamation-triangle')} <strong>#{message}</strong></p>))
  end

  def notification_icon(source)
    case source
    when 'deployment'
      icon = 'cloud-upload'
    when 'procedure'
      icon = 'cogs'
    when 'ops'
      icon = 'exclamation-triangle'
    when 'opamp'
      icon = 'bar-chart'
    when 'system'
      icon = 'exclamation-triangle'
    else
      icon = 'question-circle'
    end
    content_tag(:i, '', :class => "fa fa-#{icon}")
  end

  def button(text, btn_size = false, btn_class = false)
    size = btn_size ? "btn-#{btn_size}" : ""
    content_tag(:button, text, :class => btn_class ? "btn #{size} btn-#{btn_class}" : "btn #{size}")
  end

  def icon_button(name, text, btn_size = false, btn_class = false)
    size = btn_size ? "btn-#{btn_size}" : ""
    content_tag(:button, icon(name, text, btn_class ? true : false), :class => btn_class ? "btn #{size} btn-#{btn_class}" : "btn #{size}")
  end

  def time_ago_in_words(t)
    time_tag(t, super(t, :include_seconds => true) + ' ago', :title => t)
  end

  def time_duration_in_words(ms)
    if ms < 1000
      "#{ms} ms"
    elsif ms < 60 * 1000
      "#{(ms.to_f / 1000).round(1)} sec"
    elsif ms < 60 * 60 * 1000
      "#{(ms.to_f / (60 * 1000)).round(1)} min"
    else
      "#{(ms.to_f / (60 * 60 * 1000)).round(1)} hr"
    end
  end

  def page_alert
    if @assembly
      controller_name = controller.class.name
      if controller_name.include?('Design')
        release = @release || Cms::Release.latest(:nsPath => assembly_ns_path(@assembly))
        render 'design/page_alert', :assembly => @assembly, :release => release if release && release.releaseState == 'open'
      elsif controller_name.include?('Transition::') && @environment
        release    = @release || Cms::Release.latest(:nsPath => "#{environment_manifest_ns_path(@environment)}")
        deployment = @deployment || Cms::Deployment.latest(:nsPath => "#{environment_ns_path(@environment)}/bom")

        render 'transition/page_alert', :assembly => @assembly, :environment => @environment, :release => release, :deployment => deployment if release && release.releaseState == 'open'
      end
    end
  end

  def wizard
    return unless user_signed_in? && current_user.organization_id.present? && current_user.show_wizard?

    assembly = if @assembly && @assembly.persisted?
      @assembly.is_a?(Cms::Ci) ? @assembly : (@assembly.is_a?(Cms::Relation) ? @assembly.toCi : nil)
    else
      assemblies = locate_assemblies
      assemblies.size == 1 ? assemblies.first : nil
    end

    if assembly
      environment = @environment
      unless environment
        environments = Cms::Relation.all(:params => {:ciId              => assembly.ciId,
                                                     :direction         => 'from',
                                                     :relationShortName => 'RealizedIn',
                                                     :targetClassName   => 'manifest.Environment'})
        environment = environments.size == 1 ? environments.first.try(:toCi) : nil
      end
    end

    render 'layouts/wizard', :assembly => assembly, :environment => environment && environment.persisted? ? environment : nil
  end

  def random_dom_id
    SecureRandom.random_number(36**6).to_s(36)
  end

  def diagram
    graph = GraphViz::new( "G" )
    graph_options = {
          :truecolor  => true,
          :rankdir    => 'TB',
          :center     => true,
          :ratio      => 'fill',
          :size       => params[:size] || "6,4",
          :bgcolor    => "transparent"}
    graph[graph_options.merge(params.slice(*graph_options.keys))]
    graph.node[:fontsize  => 8,
               :fontname  => 'ArialMT',
               :fontcolor => 'black',
               :color     => 'black',
               :fillcolor => 'whitesmoke',
               :fixedsize => true,
               :width     => "2.50",
               :height    => "0.66",
               :shape     => 'rect',
               :style     => 'rounded']
    graph.edge[:fontsize  => 10,
               :fontname  => 'ArialMT',
               :fontcolor => 'black',
               :color     => 'gray']


    components = Cms::DjRelation.all(:params => {:ciId              => @platform.ciId,
                                                 :relationShortName => 'Requires',
                                                 :direction         => 'from',
                                                 :includeToCi       => true})
    components.each do |node|
      ci = node.toCi
      url = nil
      if @assembly
        if @environment
          url = edit_assembly_transition_environment_platform_component_path(@assembly, @environment, @platform, ci.id)
        else
          url = edit_assembly_design_platform_component_path(@assembly, @platform, ci.id)
        end
      elsif @catalog
        url = edit_catalog_platform_component_path(@catalog, @platform, ci.id)
      end
      img = "<img scale='both' src='#{ci_image_url(ci)}>"
      label = "<<table border='0' cellspacing='2' fixedsize='true' width='180' height='48'>"
      label << "<tr><td fixedsize='true' rowspan='2' cellpadding='4' width='40' height='40' align='center'>#{img}</td>"
      label << "<td align='left' cellpadding='0' width='124' fixedsize='true'><font point-size='12'>#{ci.ciName}</font></td></tr>"
      label << "<tr><td align='left' cellpadding='0' width='124' fixedsize='true'><font point-size='10'>#{ci.updated_timestamp.to_s(:short_us)}</font></td></tr></table>>"
      graph.add_node(node.toCiId.to_s,
                     :id => node.toCiId.to_s,
                     :target => "_parent",
                     :URL    => url,
                     :label  => label,
                     :color  => to_color(ci.rfcAction))

      Cms::DjRelation.all(:params => {:ciId => node.toCiId, :relationShortName => 'DependsOn', :direction => 'from'}).each do |edge|
        if edge.relationAttributes.flex == 'true'
          edgelabel = "<<table border='0' cellspacing='1'><tr><td border='1' colspan='2'><font point-size='12'>Scale</font></td></tr>"
          edgelabel << "<tr><td align='left'>Minimum</td><td>#{edge.relationAttributes.min}</td></tr>"
          edgelabel << "<tr><td align='left' bgcolor='#D9EDF7'>Current</td><td bgcolor='#D9EDF7'>#{edge.relationAttributes.current}</td></tr>"
          edgelabel << "<tr><td align='left'>Maximum</td><td>#{edge.relationAttributes.max}</td></tr>"
          edgelabel << "</table>>"
          graph.add_edge(edge.fromCiId.to_s, edge.toCiId.to_s,
            :labeltarget => "_parent",
            :labelURL => "#{url}",
            :minlen => 1,
            :penwidth => 1,
            :color => 'black',
            :labeldistance => 3.0,
            :arrowtail => 'odiamond',
            :dir => 'back',
            :label => edgelabel
          )
        elsif edge.relationAttributes.converge == 'true'
          edgelabel = "<<table border='0' cellspacing='1'><tr><td border='1' colspan='2'><font point-size='12'>Converge</font></td></tr></table>>"
          graph.add_edge(edge.fromCiId.to_s, edge.toCiId.to_s,
            :labeltarget => "_parent",
            :labelURL => url,
            :minlen => 1,
            :penwidth => 1,
            :color => 'black',
            :labeldistance => 3.0,
            :arrowhead => 'odiamond',
            :label => edgelabel
          )
        else
          graph.add_edge(edge.fromCiId.to_s, edge.toCiId.to_s)
        end
      end
    end

    send_data(graph.output(:svg => String), :type => 'image/svg+xml', :disposition => 'inline')
  end

  def breadcrumb_marker(count, label_class = '', options = {})
    content_tag(:span, count, options.merge(:class => "label label-breadcrumb #{label_class}"))
  end

  def breadcrumb_environment_label(env = @environment)
    profile = env.ciAttributes.attributes.has_key?(:profile) && env.ciAttributes.profile
    "#{env.ciName}#{" #{breadcrumb_marker("#{profile}", 'label-info')}" if profile}"
  end

  def breadcrumb_platform_label(platform = @platform)
    active = @platform.ciAttributes.attributes.has_key?(:is_active) && @platform.ciAttributes.is_active == 'false' ? false : true
    "#{platform.ciName} #{breadcrumb_marker("version #{platform.ciAttributes.major_version}", active ? 'label-success' : '')}"
  end

  def release_state_icon(state, additional_classes = '')
    icon = ''
    text = ''
    case state
      when 'closed'
        icon = 'check'
        text = 'text-success'
      when 'open'
        icon = 'folder-open'
        text = 'text-info'
      when 'canceled'
        icon = 'ban'
        text = 'text-error'
    end
    content_tag(:i, '', :class => "fa fa-#{icon} #{text} #{additional_classes}", :alt => state)
  end

  def deployment_state_icon(state, additional_classes = '')
    icon = ''
    text = ''
    case state
      when 'pending'
        icon = 'clock-o'
        text = 'muted'
      when 'complete'
        icon = 'check'
        text = 'text-success'
      when 'failed'
        icon = 'remove'
        text = 'text-error'
      when 'canceled'
        icon = 'ban'
        text = 'text-error'
      when 'active'
        icon = 'spinner fa-spin'
        text = 'text-info'
      when 'paused'
        icon = 'pause'
        text = 'text-warning'
      when 'pausing'
        icon = 'pause'
        text = 'text-warning'
    end
    content_tag(:i, '', :class => "fa fa-#{icon} #{text} #{additional_classes}", :alt => state)
  end

  def rfc_action_icon(action, additional_classes = '')
    icon = ''
    text = ''
    case action
      when 'add'
        icon = 'plus'
        text = 'success'
      when 'delete'
        icon = 'minus'
        text = 'error'
      when 'replace'
        icon = 'exchange'
        text = 'success'
      when 'update'
        icon = 'repeat'
        text = 'warning'
    end
    content_tag(:i, ' ', :class => "rfc-action fa fa-#{icon} text-#{text} #{additional_classes}")
  end

  def rfc_state_icon(state, additional_classes = '')
    icon = ''
    text = ''
    case state
      when 'pending'
        icon = 'clock-o'
        text = 'muted'
      when 'inprogress'
        icon = 'spinner fa-spin'
        text = ''
      when 'complete'
        icon = 'check'
        text = 'text-success'
      when 'failed'
        icon = 'remove'
        text = 'text-error'
      when 'canceled'
        icon = 'ban'
        text = 'text-error'
      when 'active'
        icon = 'spinner fa-spin'
        text = 'text-info'
    end
    content_tag(:i, '', :class => "fa fa-#{icon} #{text} #{additional_classes}", :alt => state)
  end

  def rfc_header(rfc, options)
    state            = options[:state]
    duration         = options[:duration]
    deployment_state = options[:deployment_state]
    result   = ''
    result << rfc_action_icon(rfc.rfcAction, 'fa-lg')
    result << '&nbsp;&nbsp;'
    result << %(#{highlight(rfc.nsPath.gsub(/(\/_design\/)|(\/manifest\/)|\/bom\//, '/').split('/')[3..-1].join('/'))}&nbsp;&nbsp;#{rfc.ciClassName.split('.').last} )
    result << '&nbsp;&nbsp;'
    if deployment_state && deployment_state == 'complete' && rfc.rfcAction == 'delete'
      result << %(<strong>#{rfc.ciName}</strong>)
    else
      result << %(<strong>#{link_to(rfc.ciName, path_to_ci(rfc), :onclick => "if (!event.ctrlKey && !event.shiftKey && !event.metaKey) show_busy(' '); event.stopPropagation()")}</strong>)
    end
    result << '<span class="pull-right">'
    result <<   %(<small id="rfc_<%= rfc.rfcId %>_duration">#{time_duration_in_words(duration) if duration && duration > 0 }</small>)
    result <<   %(<span class="rfc-state">#{rfc_state_icon(state)}</span>) if state
    result << '</span>'
    raw(result)
  end

  def rfc_properties(rfc)
    result = '<dl class="dl-horizontal">'
    result << '<dt>RfcId</dt>'
    result << "<dd>#{rfc.rfcId}</dd>"
    if rfc.is_a?(Cms::RfcCi)
      result << '<dt>Ci</dt>'
      result << "<dd>#{rfc.ciId}</dd>"
    else
      result << '<dt>Relation</dt>'
      result << "<dd>#{rfc.ciRelationId}</dd>"
    end
    result << '<dt>Release</dt>'
    result << "<dd>#{rfc.releaseId}</dd>"
    if rfc.is_a?(Cms::RfcCi)
      result << '<dt>Created</dt>'
      result << "<dd>#{time_ago_in_words(rfc.rfc_created_timestamp) } by #{rfc.rfcCreatedBy }</dd>" if rfc.rfcCreated
      unless rfc.rfcCreated == rfc.rfcUpdated
        result << '<dt>Updated</dt>'
        result << "<dd>#{time_ago_in_words(rfc.rfc_updated_timestamp)}#{" by #{rfc.rfcUpdatedBy}" if rfc.rfcUpdatedBy}</dd>" if rfc.rfcUpdated
      end
    else
      result << '<dt>Created</dt>'
      result << "<dd>#{time_ago_in_words(rfc.created_timestamp) } by #{rfc.createdBy }</dd>" if rfc.created
      unless rfc.created == rfc.updated
        result << '<dt>Updated</dt>'
        result << "<dd>#{time_ago_in_words(rfc.updated_timestamp)}#{" by #{rfc.updatedBy}" if rfc.updatedBy}</dd>" if rfc.updated
      end
    end
    result << '</dl>'
    raw(result)
  end

  def rfc_attributes(rfc)
    result = '<dl class="dl-horizontal">'
    (rfc.is_a?(Cms::RfcCi) ? rfc.ciAttributes : rfc.relationAttributes).attributes.each do |attr_name, attr_value|
      md_attribute = rfc.meta.md_attribute(attr_name)
      description = md_attribute.description.presence || attr_name
      data_type   = md_attribute.dataType
      json        = data_type == 'hash' || data_type == 'array' || data_type == 'struct'
      attr_value  = JSON.parse(attr_value) if json && attr_value.present?
      result << %(<dt title="#{ description }">#{ description }</dt>)
      result << %(<dd class="diff-container">)
      if attr_value.blank?
        result << '&nbsp;'
      else
        result << %(<pre>#{json && attr_value.present? ? JSON.pretty_unparse(attr_value) : attr_value}</pre>)
      end
      result << '</dd>'
    end
    result << '</dl>'
    raw(result)
  end

  def hash_list(data)
    result = '<dl class="dl-horizontal">'
    data.each_pair do |name, value|
      result << %(<dt title="#{ name }">#{ name }</dt>
                  <dd>#{ value.presence || '&nbsp;' }</dd>)
      end
    result << '</dl>'
    raw(result)
  end

  def site_icon(name)
    SITE_ICONS[name.to_sym] || name
  end

  def site_icon!(name)
    SITE_ICONS[name.to_sym]
  end

  def general_site_links
    return GENERAL_SITE_LINKS
  end

  def team_list_permission_marking(team)
    result = %w(manages_access org_scope).inject('') do |a, perm|
      a << icon(site_icon(perm), '&nbsp;&nbsp;', 'fa-lg text-error') if team.name == Team::ADMINS || team.send("#{perm}?")
      a
    end
    result = %w(cloud_services cloud_compliance cloud_support design transition operations).inject(result) do |a, perm|
      a << icon(site_icon(perm), '&nbsp;&nbsp;', 'fa-lg') if team.send("#{perm}?")
      a
    end
    raw(result)
  end

  def cost_donut(data, category, title, &block)
    total  = data[:total]
    if total && total > 0
      unit       = data[:unit]
      slices     = {}
      max_slices = 10
      data[category].to_a.sort_by(&:last).reverse.each_with_index do |bucket, i|
        key  = bucket.first
        name = block_given? ? yield(key) : key
        cost = bucket.last + (slices[name] ? slices[name][:value] : 0)
        slices[name] = {:name => name,
                        :value => cost,
                        :label => "#{name} - #{number_with_precision(100 * cost / total, :precision => 1)}% (#{number_with_precision(cost, :precision => 2, :delimiter => ',')} #{unit})"}
      end

      slices_count = slices.size
      slices = slices.values.
        sort_by {|s| -s[:value]}[0..(max_slices - 2)].
        select {|s| s[:value] / total > 0.02}.
        to_map {|s| s[:name]}
      if slices.size < slices_count
        name = 'others'
        cost = total - slices.values.sum { |s| s[:value] }
        slices[name] = {:name  => name,
                        :value => cost,
                        :label => "#{name} - #{number_with_precision(100.0 * cost / total, :precision => 1)}% (#{number_with_precision(cost, :precision => 2, :delimiter => ',')} #{unit})"}
      end
      data = {:title  => title,
              :label  => slices_count,
              :slices => slices.values}
      legend = nil
    else
      data   = {:title  => title,
                :label  => 'N/A',
                :slices => [{:name => 'N/A', :value => 1, :label => 'Data not available'}]}
      legend = [{:name => 'N/A', :color => '#aaa'}]
    end

    render 'base/shared/graph_donut', :data => {:data => [data], :legend => legend}, :legend => false
  end

  def ci_doc_link(ci, label, opts = {})
    asset_url = Settings.asset_url.presence || 'cms/'
    anchor    = opts[:anchor]
    link_to(raw(label),
            "#{asset_url}#{ci.ciClassName.split('.')[1..-1].join('.')}/index.html#{"##{anchor}" if anchor.present?}",
            :target => '_blank',
            :class  => opts[:class] || '')
  end

  def platform_doc_link(platform, label, opts = {})
    asset_url = Settings.asset_url.presence || 'cms/'
    ci_attrs  = platform.ciAttributes
    pack      = ci_attrs.pack
    anchor    = opts[:anchor]
    link_to(raw(label),
            "#{asset_url}public/#{ci_attrs.source}/packs/#{pack}/#{ci_attrs.version}/#{pack}.html#{"##{anchor}" if anchor.present?}",
            :target => '_blank',
            :class  => opts[:class] || '')
  end
end
