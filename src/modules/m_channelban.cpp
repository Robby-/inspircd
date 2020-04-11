/*
 * InspIRCd -- Internet Relay Chat Daemon
 *
 *   Copyright (C) 2013 Sadie Powell <sadie@witchery.services>
 *   Copyright (C) 2012, 2019 Robby <robby@chatbelgie.be>
 *   Copyright (C) 2012, 2014-2016 Attila Molnar <attilamolnar@hush.com>
 *   Copyright (C) 2010 Craig Edwards <brain@inspircd.org>
 *   Copyright (C) 2009 Uli Schlachter <psychon@inspircd.org>
 *   Copyright (C) 2009 Daniel De Graaf <danieldg@inspircd.org>
 *   Copyright (C) 2008 Robin Burchell <robin+git@viroteck.net>
 *
 * This file is part of InspIRCd.  InspIRCd is free software: you can
 * redistribute it and/or modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation, version 2.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


#include "inspircd.h"
#include "modules/isupport.h"

class ModuleBadChannelExtban
	: public Module
	, public ISupport::EventListener
{
 public:
	ModuleBadChannelExtban()
		: Module(VF_VENDOR | VF_OPTCOMMON, "Adds the j extended ban which checks whether users are in a channel matching the specified glob pattern.")
		, ISupport::EventListener(this)
	{
	}

	ModResult OnCheckBan(User *user, Channel *c, const std::string& mask) override
	{
		if ((mask.length() > 2) && (mask[0] == 'j') && (mask[1] == ':'))
		{
			std::string rm(mask, 2);
			char status = 0;
			const PrefixMode* const mh = ServerInstance->Modes.FindPrefix(rm[0]);
			if (mh)
			{
				rm.assign(mask, 3, std::string::npos);
				status = mh->GetModeChar();
			}
			for (User::ChanList::iterator i = user->chans.begin(); i != user->chans.end(); i++)
			{
				if (InspIRCd::Match((*i)->chan->name, rm))
				{
					if ((!status) || ((*i)->HasMode(mh)))
						return MOD_RES_DENY;
				}
			}
		}
		return MOD_RES_PASSTHRU;
	}

	void OnBuildISupport(ISupport::TokenMap& tokens) override
	{
		tokens["EXTBAN"].push_back('j');
	}
};

MODULE_INIT(ModuleBadChannelExtban)
