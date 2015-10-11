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
	 * Show workspace name after workspace switched.
	 */
	// TODO: rename to DeepinWorkspaceNamePopup
	public class DeepinWorkspaceName : Clutter.Actor
	{
		const int FADE_DURATION = 200;
		const AnimationMode FADE_MODE = AnimationMode.EASE_OUT_CUBIC;

		const int POPUP_TIMEOUT = 200;
		const int POPUP_PADDING = 14;
		const int POPUP_MAX_WIDTH = 300;

		public Screen screen { get; construct; }

		Actor popup;
		Text workspace_name;

		uint popup_timeout_id = 0;

		public DeepinWorkspaceName (Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			popup = new DeepinCssStaticActor ("deepin-workspace-name");
			popup.opacity = 0;
			popup.set_easing_duration (FADE_DURATION);
			popup.set_easing_mode (FADE_MODE);
			popup.layout_manager = new BoxLayout ();
			popup.add_constraint (new AlignConstraint (this, AlignAxis.BOTH, 0.5f));

			var font = DeepinUtils.get_css_font ("deepin-workspace-name");

			workspace_name = new Text ();
			workspace_name.margin_bottom = POPUP_PADDING;
			workspace_name.margin_left = POPUP_PADDING;
			workspace_name.margin_right = POPUP_PADDING;
			workspace_name.margin_top = POPUP_PADDING;
			workspace_name.activatable = true;
			workspace_name.ellipsize = Pango.EllipsizeMode.END;
			workspace_name.single_line_mode = true;
			workspace_name.set_font_description (font);
			workspace_name.color = DeepinUtils.get_css_color ("deepin-workspace-name");

			popup.add_child (workspace_name);

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
			update_workspace_name ();

			// reset timer and trasition
			if (popup_timeout_id != 0) {
				Source.remove (popup_timeout_id);
				popup_timeout_id = 0;
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
				transition.completed.connect (start_timer);
			} else {
				start_timer ();
			}
		}

		void start_timer ()
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

			var name = DeepinUtils.get_workspace_name (active_index);
			if (name.length > 0) {
				workspace_name.text = "%d  %s".printf (active_index + 1, name);
			} else {
				workspace_name.text = "%d".printf (active_index + 1);
			}
		}
	}
}
