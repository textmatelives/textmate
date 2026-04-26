#ifndef FS_EVENTS_H_QDH73MIO
#define FS_EVENTS_H_QDH73MIO

namespace scm
{
	// Returns true for FSEvents paths inside `.git/` that represent
	// transient git plumbing (lockfiles, fsmonitor daemon IPC) rather
	// than working-tree changes. Public for unit testing.
	bool is_transient_git_path (std::string const& path);

	struct watcher_t
	{
		watcher_t (std::string const& path, std::function<void(std::set<std::string> const&)> const& callback);
		~watcher_t ();

	private:
		static void callback_function (ConstFSEventStreamRef streamRef, void* clientCallBackInfo, size_t numEvents, void* eventPaths, FSEventStreamEventFlags const eventFlags[], FSEventStreamEventId const eventIds[]);
		void invoke_callback (std::set<std::string> const& changedPaths);

		std::string path;
		std::function<void(std::set<std::string> const&)> callback;

		std::string mount_point;
		FSEventStreamRef stream;
	};

} /* scm */

#endif /* end of include guard: FS_EVENTS_H_QDH73MIO */
