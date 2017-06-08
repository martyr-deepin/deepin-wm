//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Clutter;
using Meta;

namespace Gala
{
	/**
	 * Base class for alt-tab list items.
	 */
	public class DeepinWindowSwitcherItem : Actor
	{
		/**
		 * Prefer size for current item.
		 */
		public const int PREFER_WIDTH = 300;
		public const int PREFER_HEIGHT = 200;

		/**
		 * Prefer size for the inner item's rectangle.
		 */
		public const int RECT_PREFER_WIDTH = PREFER_WIDTH - SHAPE_PADDING * 2;
		public const int RECT_PREFER_HEIGHT = PREFER_HEIGHT - SHAPE_PADDING * 2;

		protected const int SHAPE_PADDING = 10;

		/**
		 * The window was resized and a relayout of the tiling layout may
		 * be sensible right now.
		 */
		public signal void request_reposition ();

		public DeepinWindowSwitcherItem ()
		{
			Object ();
		}

		construct
		{
			x_align = ActorAlign.FILL;
			y_align = ActorAlign.FILL;
		}
	}

	/**
	 * Desktop item in alt-tab list, which owns the background. This item always
	 * be put in last and will show desktop if activated.
	 */
	public class DeepinWindowSwitcherDesktopItem : DeepinWindowSwitcherItem
	{
		public Screen screen { get; construct; }

		DeepinFramedBackground background;

        // when item is too small, show desktop icon instead
        bool show_icon = false;
        GtkClutter.Texture desktop_icon;

		public DeepinWindowSwitcherDesktopItem (Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			float scale_x = RECT_PREFER_WIDTH / (float)monitor_geom.width;
			float scale_y = RECT_PREFER_HEIGHT / (float)monitor_geom.height;
			float scale = Math.fminf (scale_x, scale_y);

			background = new DeepinFramedBackground (screen, screen.get_active_workspace_index (),
													 false, false, scale);
            desktop_icon = load_icon ();
            desktop_icon.visible = show_icon;
            set_show_icon (false);

			add_child (background);
            add_child (desktop_icon);
		}

        public void set_show_icon (bool val) 
        {
            if (show_icon != val) {
                show_icon = val;

                background.visible = !show_icon;
                desktop_icon.visible = show_icon;
            }
        }

		GtkClutter.Texture load_icon ()
		{
			var texture = new GtkClutter.Texture ();
			var pixbuf = get_button_pixbuf ();


			if (pixbuf != null) {
				try {
					texture.set_from_pixbuf (pixbuf);
				} catch (Error e) {}
			} else {
				// we'll just make this red so there's at least something as an
				// indicator that loading failed. Should never happen and this
				// works as good as some weird fallback-image-failed-to-load pixbuf
				texture.background_color = { 255, 0, 0, 255 };
			}

			return texture;
		}

		Gdk.Pixbuf? get_button_pixbuf ()
        {
            Gdk.Pixbuf? pixbuf;

            try {
                pixbuf = new Gdk.Pixbuf.from_file (Config.PKGDATADIR + "/" + "deepin-toggle-desktop.svg");
            } catch (Error e) {
                warning (e.message);
                return null;
            }

            return pixbuf;
        }

		/**
		 * Calculate the preferred size for background.
		 */
		void get_background_preferred_size (out float width, out float height)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			float scale_x = RECT_PREFER_WIDTH / (float)monitor_geom.width;
			float scale_y = RECT_PREFER_HEIGHT / (float)monitor_geom.height;
			float scale = Math.fminf (scale_x, scale_y);

			width = (float)monitor_geom.width * scale;
			height = (float)monitor_geom.height * scale;
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			float scale = box.get_width () / PREFER_WIDTH;

			var bg_box = ActorBox ();
			float bg_width, bg_height;
			float bg_prefer_width, bg_prefer_height;
			get_background_preferred_size (out bg_prefer_width, out bg_prefer_height);
			bg_width = bg_prefer_width * scale;
			bg_height = bg_prefer_height * scale;
			bg_box.set_size (bg_width, bg_height);
			bg_box.set_origin ((box.get_width () - bg_box.get_width ()) / 2,
							   (box.get_height () - bg_box.get_height ()) / 2);

            if (background.visible) {
                // scale background to relative to preferred size
                background.scale_x = scale;
                background.scale_y = scale;

                background.allocate (bg_box, flags);
            }

            if (desktop_icon.visible) {
                var icon_box = ActorBox ();
				icon_box.set_size (48, 48);
				icon_box.set_origin (
					(box.get_width () - icon_box.get_width ()) / 2,
					(box.get_height () - icon_box.get_height ()) / 2);
                desktop_icon.allocate (icon_box, flags);
            }
		}
	}

	/**
	 * Window item in alt-tab list, which is a container for a clone of the texture of MetaWindow, a
	 * WindowIcon and a shadow.
	 */
	public class DeepinWindowSwitcherWindowItem : DeepinWindowSwitcherItem
	{
		const int ICON_SIZE = 58;

		public Window window { get; construct; }

		uint shadow_update_timeout_id = 0;
		bool enable_shadow = false;

		Actor? clone_container = null;  // container for clone to add shadow effect
		Clone? clone = null;
		GtkClutter.Texture window_icon;

		public DeepinWindowSwitcherWindowItem (Window window)
		{
			Object (window: window);
		}

		construct
		{
			window.unmanaged.connect (on_unmanaged);
			window.workspace_changed.connect (on_workspace_changed);
			window.notify["on-all-workspaces"].connect (on_all_workspaces_changed);

			window_icon = new WindowIcon (window, ICON_SIZE);
			window_icon.set_pivot_point (0.5f, 0.5f);

			add_child (window_icon);

			load_clone ();
		}

		~DeepinWindowSwitcherWindowItem ()
		{
			window.unmanaged.disconnect (on_unmanaged);
			window.workspace_changed.disconnect (on_workspace_changed);
			window.notify["on-all-workspaces"].disconnect (on_all_workspaces_changed);

			if (shadow_update_timeout_id != 0) {
				Source.remove (shadow_update_timeout_id);
			}

			window.size_changed.disconnect (on_window_size_changed);
		}

        public bool show_icon_only ()
        {
            return clone_container == null || !clone_container.visible;
        }

		/**
		 * The window unmanaged by the compositor, so we need to destroy ourselves too.
		 */
		void on_unmanaged ()
		{
			if (clone_container != null) {
				clone_container.destroy ();
			}

			if (shadow_update_timeout_id != 0) {
				Source.remove (shadow_update_timeout_id);
				shadow_update_timeout_id = 0;
			}

			destroy ();
		}

		void on_workspace_changed ()
		{
			check_is_window_in_active_workspace ();
		}
		void on_all_workspaces_changed ()
		{
			check_is_window_in_active_workspace ();
		}
		void check_is_window_in_active_workspace ()
		{
			// we don't display windows that are moved to other workspace
			if (!DeepinUtils.is_window_in_tab_list (window)) {
				on_unmanaged ();
			}
		}

		void on_window_size_changed ()
		{
			request_reposition ();
		}

		/**
		 * Waits for the texture of a new WindowActor to be available and makes a close of it. If it
		 * was already was assigned a slot at this point it will animate to it. Otherwise it will
		 * just place itself at the location of the original window. Also adds the shadow effect and
		 * makes sure the shadow is updated on size changes.
		 */
		void load_clone ()
		{
			var actor = window.get_compositor_private () as WindowActor;
			if (actor == null) {
				Idle.add (() => {
					if (window.get_compositor_private () != null) {
						load_clone ();
					}
					return false;
				});

				return;
			}

			clone_container = new Actor ();
			clone = new Clone (actor.get_texture ());
			clone.add_constraint (new BindConstraint (clone_container, BindCoordinate.SIZE, 0));
			clone_container.add_child (clone);

			add_child (clone_container);

			set_child_above_sibling (window_icon, clone_container);

			window.size_changed.connect (on_window_size_changed);
		}

		Meta.Rectangle get_window_outer_rect ()
		{
			var outer_rect = window.get_frame_rect ();
			return outer_rect;
		}

		/**
		 * Calculate the preferred size for window clone.
		 */
		void get_clone_preferred_size (out float width, out float height)
		{
			var outer_rect = get_window_outer_rect ();
			float scale_x = RECT_PREFER_WIDTH / (float)outer_rect.width;
			float scale_y = RECT_PREFER_HEIGHT / (float)outer_rect.height;
			float scale = Math.fminf (scale_x, scale_y);

			width = outer_rect.width * scale;
			height = outer_rect.height * scale;
		}

		void update_shadow_async (uint interval, int width, int height)
		{
			if (shadow_update_timeout_id != 0) {
				Source.remove (shadow_update_timeout_id);
				shadow_update_timeout_id = 0;
			}

			shadow_update_timeout_id = Timeout.add (interval, () => {
				do_update_shadow (width, height);
				shadow_update_timeout_id = 0;
				return false;
			});
		}
		void do_update_shadow (int width, int height)
		{
			if (clone_container == null) {
				return;
			}

			var shadow_effect = clone_container.get_effect ("shadow") as ShadowEffect;
			if (shadow_effect == null) {
				shadow_effect = new ShadowEffect (width, height, 40, 5);
				clone_container.add_effect_with_name ("shadow", shadow_effect);
			} else {
				shadow_effect.update_size (width, height);
			}
		}

		/**
		 * Except for the texture clone and the highlight all children are placed according to their
		 * given allocations. The first two are placed in a way that compensates for invisible
		 * borders of the texture.
		 */
		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			float scale = box.get_width () / PREFER_WIDTH;

			var icon_box = ActorBox ();
			var icon_width = window_icon.width;
			var icon_height = window_icon.height;
			if (box.get_width () <= icon_width * 2.5f) {
				if (box.get_width () >= icon_width) {
					icon_box.set_size (icon_width, icon_height);
				} else {
					float fixed_icon_size = Math.fminf (box.get_width (), box.get_height ());
					if (fixed_icon_size > SHAPE_PADDING * 2 * scale) {
						fixed_icon_size -= SHAPE_PADDING * 2 * scale;
					}
					icon_box.set_size (fixed_icon_size, fixed_icon_size);
				}
				icon_box.set_origin ((box.get_width () - icon_box.get_width ()) / 2,
									 (box.get_height () - icon_box.get_height ()) / 2 +
									 WindowIcon.SHADOW_SIZE);
			} else {
				icon_box.set_size (icon_width, icon_height);
				icon_box.set_origin (
					(box.get_width () - icon_box.get_width ()) / 2,
					box.get_height () - icon_box.get_height () - icon_box.get_height () * 0.25f +
					WindowIcon.SHADOW_SIZE);
			}
			window_icon.allocate (icon_box, flags);

			// if actor's size is really small, just show icon only
			if (box.get_width () <= icon_width * 1.75f) {
				if (clone_container != null) {
					// set clone visible to false manually to hide shadow effect
					clone_container.visible = false;
				}
				return;
			}

			if (clone_container == null) {
				return;
			}

			clone_container.visible = true;  // reset clone visible

			var clone_box = ActorBox ();
			float clone_width, clone_height;
			float clone_prefer_width, clone_prefer_height;
			get_clone_preferred_size (out clone_prefer_width, out clone_prefer_height);
			clone_width = clone_prefer_width * scale;
			clone_height = clone_prefer_height * scale;
			clone_box.set_size (clone_width, clone_height);
			clone_box.set_origin ((box.get_width () - clone_box.get_width ()) / 2,
								  (box.get_height () - clone_box.get_height ()) / 2);

			clone_container.allocate (clone_box, flags);

			if (enable_shadow) {
				update_shadow_async (0, (int)clone_width, (int)clone_height);
			}
		}
	}
}
