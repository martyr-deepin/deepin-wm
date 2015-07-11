//
//  Copyright (C) 2014 Xu Fasheng, Deepin, Inc.
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
	 * Show the name after switching workspace.
	 */
	public class DeepinWorkspaceName : Clutter.Actor
	{
		const int ANIMATION_DURATION = 200;
		const AnimationMode ANIMATION_MODE = AnimationMode.EASE_OUT_CUBIC;

		const int POPUP_TIMEOUT = 100;
		const int POPUP_PADDING = 20;
		const int POPUP_MAX_WIDTH = 300;

		const int LAYOUT_SPACING = 12;

		public Screen screen { get; construct; }

		Actor popup;
		Actor container;
		Text worksapce_num;
		Text worksapce_name;

		uint popup_timeout_id = 0;

		public DeepinWorkspaceName (Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			popup = new DeepinCssStaticActor ("deepin-workspace-name");
			popup.opacity = 0;
			popup.set_easing_duration (ANIMATION_DURATION);
			popup.set_easing_mode (ANIMATION_MODE);
			popup.layout_manager = new BoxLayout ();

			container = new Actor ();
			container.margin_bottom = POPUP_PADDING;
			container.margin_left = POPUP_PADDING;
			container.margin_right = POPUP_PADDING;
			container.margin_top = POPUP_PADDING;
			container.layout_manager = new BoxLayout ();
			popup.add_child (container);

			var font = DeepinUtils.get_css_font ("deepin-workspace-name");

			worksapce_num = new Text ();
			worksapce_num.set_font_description (font);
			worksapce_num.color = DeepinUtils.get_css_color ("deepin-workspace-name");
			container.add_child (worksapce_num);

			worksapce_name = new Text ();
			worksapce_name.activatable = true;
			worksapce_name.ellipsize = Pango.EllipsizeMode.END;
			worksapce_name.single_line_mode = true;
			worksapce_name.set_font_description (font);
			worksapce_name.color = DeepinUtils.get_css_color ("deepin-workspace-name");
			container.add_child (worksapce_name);

			add_child (popup);

			update_workspace_name ();

			visible = false;
		}

		~DeepinWorkspaceName ()
		{
			if (popup_timeout_id != 0) {
				Source.remove (popup_timeout_id);
			}
		}

		public void show_popup ()
		{
			// reset timer and trasition
			if (popup_timeout_id != 0) {
				Source.remove (popup_timeout_id);
			}
			var transition = popup.get_transition ("opacity");
			if (transition != null) {
				popup.remove_transition ("opacity");
			}

			visible = true;
			popup.opacity = 255;

			// start timer after popup shown
			transition = popup.get_transition ("opacity");
			if (transition != null) {
				transition.completed.connect (setup_timer);
			} else {
				setup_timer ();
			}
		}

		void setup_timer ()
		{
			popup_timeout_id = Timeout.add (POPUP_TIMEOUT, () => {
				hide_popup ();
				popup_timeout_id = 0;
				return false;
			});
		}

		void hide_popup ()
		{
			popup.opacity = 0;

			var transition = popup.get_transition ("opacity");

			if (transition != null) {
				transition.completed.connect (() => visible = false);
			} else {
				visible = false;
			}
		}

		void update_workspace_name ()
		{
			int active_index = screen.get_active_workspace_index ();
			worksapce_num.text = "%d".printf (active_index + 1);
			worksapce_name.text = DeepinUtils.get_workspace_name (active_index);

			var layout = container.layout_manager as BoxLayout;
			if (worksapce_name.text.length == 0) {
				layout.spacing = 0;
			} else {
				layout.spacing = LAYOUT_SPACING;
			}
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			update_workspace_name ();

			var popup_box = new ActorBox ();
			popup_box.set_size (Math.fminf (container.width, POPUP_MAX_WIDTH), container.height);
			popup_box.set_origin ((monitor_geom.width - popup_box.get_width ()) / 2,
								  (monitor_geom.height - popup_box.get_height ()) / 2);
			popup.allocate (popup_box, flags);
		}
	}
}
