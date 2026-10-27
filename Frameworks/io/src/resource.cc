#include "resource.h"
#include "path.h"
#include <cf/cf.h>

namespace path
{
	std::string resource (std::string const& path, ResType theType, ResID theID)
	{
		std::string res = NULL_STR;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		FSRef fsref;
		if(noErr != FSPathMakeRefWithOptions((UInt8 const*)path.c_str(), kFSPathMakeRefDoNotFollowLeafSymlink, &fsref, NULL))
		{
			if(ResFileRefNum ref = FSOpenResFile(&fsref, fsRdPerm))
			{
				if(Handle handle = Get1Resource(theType, theID))
				{
					HLock(handle);
					res = std::string(*handle, *handle + GetHandleSize(handle));
					HUnlock(handle);
					ReleaseResource(handle);
				}
				CloseResFile(ref);
			}
		}
#pragma clang diagnostic pop
		return res;
	}

} /* path */
