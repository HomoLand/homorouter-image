'use strict';
'require baseclass';
'require ui';

var CATEGORY_ICONS = {
	status:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="3" width="8" height="8"/><rect x="13" y="3" width="8" height="5"/><rect x="13" y="10" width="8" height="11"/><rect x="3" y="13" width="8" height="8"/></svg>',
	system:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.01a1.65 1.65 0 0 0 .99-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.01a1.65 1.65 0 0 0 1.51.99H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
	services:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5 12 2"/><circle cx="12" cy="12" r="3"/></svg>',
	network:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M12 2L4 5.5V11.5C4 16.8 7.4 21.4 12 22.8C16.6 21.4 20 16.8 20 11.5V5.5L12 2Z"/><path d="M9 12L11 14L15.5 9.5"/></svg>',
	vpn:        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="4" y="11" width="16" height="10"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>',
	nas:        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="4" width="18" height="7"/><rect x="3" y="13" width="18" height="7"/><circle cx="7" cy="7.5" r="1"/><circle cx="7" cy="16.5" r="1"/></svg>',
	docker:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><rect x="3" y="10" width="5" height="5"/><rect x="9" y="10" width="5" height="5"/><rect x="15" y="10" width="5" height="5"/><rect x="9" y="4" width="5" height="5"/></svg>',
	statistics: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><polyline points="3 17 9 11 13 15 21 7"/><polyline points="16 7 21 7 21 12"/></svg>',
	logout:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>',
	_default:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><polygon points="12 3 21 8 21 16 12 21 3 16 3 8 12 3"/></svg>'
};

return baseclass.extend({
	__init__: function() {
		this.commands = [];
		this.filteredCommands = [];
		this.selectedCmdIdx = 0;

		this.initChrome();
		ui.menu.load().then(L.bind(this.render, this));
	},

	initChrome: function() {
		var root = document.documentElement;
		var shell = document.getElementById('ef-shell');
		var modeBtn = document.getElementById('ef-mode-toggle');
		var modeLabel = document.getElementById('ef-mode-label');
		var collapseBtn = document.getElementById('ef-collapse-sidebar');
		var mobileBtn = document.getElementById('ef-mobile-menu-btn');
		var drawerBackdrop = document.getElementById('ef-drawer-backdrop');

		function syncModeUI() {
			var isDark = root.getAttribute('data-darkmode') === 'true';
			if (modeLabel) modeLabel.textContent = isDark ? 'DARK' : 'LIGHT';
			if (modeBtn) {
				var sun = modeBtn.querySelector('[data-mode-icon="sun"]');
				var moon = modeBtn.querySelector('[data-mode-icon="moon"]');
				if (sun) sun.style.display = isDark ? 'block' : 'none';
				if (moon) moon.style.display = isDark ? 'none' : 'block';
			}
		}

		this.toggleDarkMode = function() {
			var next = root.getAttribute('data-darkmode') !== 'true';
			root.setAttribute('data-darkmode', next ? 'true' : 'false');
			try { localStorage.setItem('luci_endfield_darkmode', next ? 'true' : 'false'); } catch (e) {}
			syncModeUI();
		};

		syncModeUI();
		if (modeBtn) {
			modeBtn.addEventListener('click', this.toggleDarkMode);
		}

		// Restore sidebar collapse state
		try {
			if (shell && localStorage.getItem('luci_endfield_collapsed') === 'true') {
				shell.classList.add('sidebar-collapsed');
			}
		} catch (e) {}

		this.toggleSidebar = function() {
			if (!shell) return;
			shell.classList.toggle('sidebar-collapsed');
			var collapsed = shell.classList.contains('sidebar-collapsed');
			try { localStorage.setItem('luci_endfield_collapsed', collapsed ? 'true' : 'false'); } catch (e) {}
		};

		if (collapseBtn) {
			collapseBtn.addEventListener('click', this.toggleSidebar);
		}

		if (mobileBtn && shell) {
			mobileBtn.addEventListener('click', function() {
				shell.classList.toggle('mobile-drawer-open');
			});
		}

		if (drawerBackdrop && shell) {
			drawerBackdrop.addEventListener('click', function() {
				shell.classList.remove('mobile-drawer-open');
			});
		}

		this.initCommandPalette();
	},

	initCommandPalette: function() {
		var self = this;
		var trigger = document.getElementById('ef-cmd-trigger');
		var backdrop = document.getElementById('ef-cmd-backdrop');
		var input = document.getElementById('ef-cmd-input');

		if (!backdrop || !input) return;

		this.openCommandPalette = function() {
			backdrop.classList.add('open');
			input.value = '';
			self.selectedCmdIdx = 0;
			self.renderCommandList();
			setTimeout(function() { input.focus(); }, 10);
		};

		this.closeCommandPalette = function() {
			backdrop.classList.remove('open');
		};

		if (trigger) {
			trigger.addEventListener('click', this.openCommandPalette);
		}

		backdrop.addEventListener('click', function(ev) {
			if (ev.target === backdrop) self.closeCommandPalette();
		});

		input.addEventListener('input', function() {
			self.selectedCmdIdx = 0;
			self.renderCommandList();
		});

		input.addEventListener('keydown', function(ev) {
			if (ev.key === 'ArrowDown') {
				ev.preventDefault();
				if (self.filteredCommands.length) {
					self.selectedCmdIdx = (self.selectedCmdIdx + 1) % self.filteredCommands.length;
					self.renderCommandList();
				}
			} else if (ev.key === 'ArrowUp') {
				ev.preventDefault();
				if (self.filteredCommands.length) {
					self.selectedCmdIdx = (self.selectedCmdIdx - 1 + self.filteredCommands.length) % self.filteredCommands.length;
					self.renderCommandList();
				}
			} else if (ev.key === 'Enter') {
				ev.preventDefault();
				self.executeCommand(self.selectedCmdIdx);
			} else if (ev.key === 'Escape') {
				ev.preventDefault();
				self.closeCommandPalette();
			}
		});

		document.addEventListener('keydown', function(ev) {
			if ((ev.ctrlKey || ev.metaKey) && ev.key && ev.key.toLowerCase() === 'k') {
				ev.preventDefault();
				if (backdrop.classList.contains('open')) self.closeCommandPalette();
				else self.openCommandPalette();
			} else if (ev.key === 'Escape' && backdrop.classList.contains('open')) {
				self.closeCommandPalette();
			} else if (ev.key === '[' && !/INPUT|TEXTAREA|SELECT/.test((document.activeElement && document.activeElement.tagName) || '')) {
				self.toggleSidebar();
			}
		});
	},

	renderCommandList: function() {
		var self = this;
		var input = document.getElementById('ef-cmd-input');
		var list = document.getElementById('ef-cmd-list');
		if (!list || !input) return;

		var q = (input.value || '').trim().toLowerCase();
		this.filteredCommands = this.commands.filter(function(c) {
			if (!q) return true;
			return c.title.toLowerCase().indexOf(q) !== -1 ||
				c.category.toLowerCase().indexOf(q) !== -1 ||
				c.desc.toLowerCase().indexOf(q) !== -1;
		}).slice(0, 30);

		if (this.selectedCmdIdx >= this.filteredCommands.length) {
			this.selectedCmdIdx = Math.max(0, this.filteredCommands.length - 1);
		}

		list.innerHTML = '';

		if (!this.filteredCommands.length) {
			list.appendChild(E('div', { 'class': 'ef-cmd-empty' }, [_('No matching commands')]));
			return;
		}

		this.filteredCommands.forEach(function(cmd, idx) {
			var item = E('button', {
				'type': 'button',
				'class': 'ef-cmd-item' + (idx === self.selectedCmdIdx ? ' selected' : ''),
				'click': function() { self.executeCommand(idx); }
			}, [
				E('span', { 'class': 'ef-cmd-item-left' }, [
					E('span', { 'class': 'ef-cmd-item-title' }, [cmd.title]),
					E('span', { 'class': 'ef-cmd-item-desc' }, [cmd.desc])
				]),
				E('span', { 'class': 'ef-cmd-cat' }, [cmd.category])
			]);
			list.appendChild(item);
		});
	},

	executeCommand: function(idx) {
		var cmd = this.filteredCommands[idx];
		if (!cmd) return;
		this.closeCommandPalette();
		if (cmd.action) {
			cmd.action();
		} else if (cmd.url) {
			window.location.href = cmd.url;
		}
	},

	render: function(tree) {
		var node = tree;
		var url = '';

		this.commands = [
			{
				title: _('Toggle Dark / Light Mode'),
				category: 'THEME',
				desc: 'Switch Titanium Charcoal / Industrial Matte',
				action: this.toggleDarkMode
			},
			{
				title: _('Toggle Sidebar'),
				category: 'UI',
				desc: 'Shortcut: [',
				action: this.toggleSidebar
			}
		];

		this.renderModeMenu(tree);

		if (L.env.dispatchpath.length >= 3) {
			for (var i = 0; i < 3 && node; i++) {
				node = node.children ? node.children[L.env.dispatchpath[i]] : null;
				url = url + (url ? '/' : '') + L.env.dispatchpath[i];
			}
			if (node) {
				this.renderTabMenu(node, url);
			}
		}
	},

	renderModeMenu: function(tree) {
		var ul = document.getElementById('modemenu');
		var children = ui.menu.getChildren(tree);

		children.forEach(L.bind(function(child, index) {
			var isActive = L.env.requestpath.length
				? child.name === L.env.requestpath[0]
				: index === 0;

			if (ul) {
				ul.appendChild(E('li', { 'class': isActive ? 'active' : '' }, [
					E('a', { 'href': L.url(child.name) }, [_(child.title)])
				]));
			}

			if (isActive) {
				this.renderSidebarMenu(child, child.name);
			}
		}, this));

		if (ul && ul.children.length > 1) {
			ul.style.display = '';
		}
	},

	renderSidebarMenu: function(tree, baseUrl) {
		var container = document.getElementById('mainmenu');
		if (!container) return;
		container.innerHTML = '';

		var groups = ui.menu.getChildren(tree);
		var activeCat = L.env.dispatchpath[1] || '';
		var activePage = L.env.dispatchpath[2] || '';
		var crumbTag = document.getElementById('ef-crumb-tag');
		var crumbPath = document.getElementById('ef-crumb-path');

		groups.forEach(L.bind(function(cat, idx) {
			var subItems = ui.menu.getChildren(cat);
			var catTitle = _(cat.title);
			var catNum = String(idx + 1).padStart(2, '0');
			var catUrl = baseUrl + '/' + cat.name;
			var isCatActive = (cat.name === activeCat);
			var iconSvg = CATEGORY_ICONS[cat.name] || CATEGORY_ICONS._default;

			// Leaf top-level entry (e.g. Logout)
			if (!subItems.length) {
				var directHref = L.url(catUrl);
				var leafLink = E('a', {
					'class': 'ef-nav-item ef-nav-leaf-top' + (isCatActive ? ' active' : ''),
					'href': directHref,
					'title': catTitle
				}, [
					E('span', { 'class': 'ef-nav-icon' }),
					E('span', { 'class': 'ef-nav-label' }, [catTitle])
				]);
				leafLink.querySelector('.ef-nav-icon').innerHTML = iconSvg;

				var leafWrap = E('div', { 'class': 'ef-nav-group ef-nav-group-leaf' }, [leafLink]);
				container.appendChild(leafWrap);

				this.commands.push({
					title: catTitle,
					category: 'NAV',
					desc: directHref,
					url: directHref
				});

				if (isCatActive && crumbTag && crumbPath) {
					crumbTag.textContent = 'SEC-' + catNum;
					crumbPath.textContent = '';
					crumbPath.appendChild(E('strong', {}, [catTitle]));
				}
				return;
			}

			// Category with submenu children
			var groupEl = E('div', {
				'class': 'ef-nav-group' + (isCatActive ? ' open active-group' : '')
			});

			var toggleBtn = E('button', {
				'type': 'button',
				'class': 'ef-nav-cat-btn' + (isCatActive ? ' active-cat' : ''),
				'title': catTitle,
				'click': function() {
					var shell = document.getElementById('ef-shell');
					if (shell && shell.classList.contains('sidebar-collapsed')) {
						shell.classList.remove('sidebar-collapsed');
						try { localStorage.setItem('luci_endfield_collapsed', 'false'); } catch (e) {}
						groupEl.classList.add('open');
						return;
					}
					groupEl.classList.toggle('open');
				}
			}, [
				E('span', { 'class': 'ef-nav-icon' }),
				E('span', { 'class': 'ef-nav-cat-title' }, [catTitle]),
				E('span', { 'class': 'ef-nav-cat-num' }, [catNum]),
				E('span', { 'class': 'ef-nav-chevron' }, ['▸'])
			]);
			toggleBtn.querySelector('.ef-nav-icon').innerHTML = iconSvg;

			var listEl = E('ul', { 'class': 'ef-nav-sublist' });

			subItems.forEach(L.bind(function(item) {
				var itemTitle = _(item.title);
				var itemHref = L.url(catUrl, item.name);
				var isItemActive = isCatActive && (item.name === activePage);

				var a = E('a', {
					'class': 'ef-nav-subitem' + (isItemActive ? ' active' : ''),
					'href': itemHref
				}, [
					E('span', { 'class': 'ef-sub-dot' }),
					E('span', { 'class': 'ef-nav-label' }, [itemTitle])
				]);

				listEl.appendChild(E('li', {}, [a]));

				this.commands.push({
					title: itemTitle,
					category: catTitle.toUpperCase(),
					desc: catTitle + ' / ' + itemTitle,
					url: itemHref
				});

				if (isItemActive && crumbTag && crumbPath) {
					crumbTag.textContent = 'SEC-' + catNum;
					crumbPath.textContent = '';
					crumbPath.appendChild(document.createTextNode(catTitle + ' / '));
					crumbPath.appendChild(E('strong', {}, [itemTitle]));
				}
			}, this));

			groupEl.appendChild(toggleBtn);
			groupEl.appendChild(listEl);
			container.appendChild(groupEl);
		}, this));
	},

	renderTabMenu: function(tree, url, level) {
		var container = document.getElementById('tabmenu');
		if (!container) return E([]);

		var ul = E('ul', { 'class': 'tabs' });
		var children = ui.menu.getChildren(tree);
		var activeNode = null;

		children.forEach(function(child) {
			var isActive = (L.env.dispatchpath[3 + (level || 0)] == child.name);
			var activeClass = isActive ? ' active' : '';
			var className = 'tabmenu-item-%s%s'.format(child.name, activeClass);

			ul.appendChild(E('li', { 'class': className }, [
				E('a', { 'href': L.url(url, child.name) }, [_(child.title)])
			]));

			if (isActive) {
				activeNode = child;
			}
		});

		if (ul.children.length === 0) {
			return E([]);
		}

		container.appendChild(ul);
		container.style.display = '';

		if (activeNode) {
			this.renderTabMenu(activeNode, url + '/' + activeNode.name, (level || 0) + 1);
		}

		return ul;
	}
});
