# File system

```mermaid
classDiagram
    direction LR
    Filesystem --> "many" Superblock : contains
    Superblock --> "many" INode : contains
    Mount "many" ..> "1" Superblock : assoc
    DEntry "many" ..> "1" INode : link
    INode "1" -- "1" File : link
    Mount "1" .. "1" DEntry : link
    %% DEntry "*" --> "1" Superblock
    class Filesystem{
        +String name
        +List~Superblock~ sbs
        +List~Filesystem~ list
        +init()
        +register()
        +unregister()
    }
    class Mount{
        +Filesystem fs
        +INode root
        +DEntry mount
        +mount()
        +unmount()
    }
    class Superblock{
        +Filesystem *fs
        Refcount ref
        DEntry root
        INode i_root
        alloc_inode()
        destroy_inode()
        read_inode()
    }
    class INode{
        +int num
        int mode
        int uid
        int guid
        Refcount ref
        Superblock sb
        lookup()
        create()
        readlink()
        link()
        unlink()
        symlink()
        mkdir()
        rmdir()
        rename()
        setattr()
        getattr()
    }
    class DEntry{
        +String name
        INode inode
        Tree tree
        Superblock sb
        Refcount ref
        release()
    }
    class File{
        int flags
        DEntry d
        int pos
        open()
        release()
        read()
        write()
    }
```

# Related syscalls

- For file:
    - open, openat -> fd
    - close (fd)
    - read, write, lseek (fd)
    - fstat (fd)
    - dup (fd)
    - dup2, dup3 (fd, fd)
    - ftstatfs (fd)
    - statx (fd)
    - cachestat (fd)
    - mmap (fd)
    - ioctl (fd)
    - fcntl (fd)
    - flock (fd)
    - fsync (fd)
    - fdatasync (fd)
    - truncate (path)
    - ftruncate (fd)
    - getdents (fd)
    - fchdir (fd)
    - creat (path) -> fd
    - fchmod, fchmodat (fd)
    - fchown, fchownat (fd)
    - futimens, utimensat (fd)
    - poll (fd)
    - select (fd)
    - inotify_init, inotify_add_watch, inotify_rm_watch
    - splice (fd, fd)
    - tee (fd, fd)
    - sync_file_range (fd)
    - copy_file_range (fd, fd)
- For dentry:
    - stat, ftsatat, lstat (path)
    - access (path)
    - getcwd -> path
    - chdir (path)
    - rename, renameat (path, path)
    - mkdir, mkdirat (path)
    - rmdir (path)
    - link, linkat (path, path)
    - unlink, unlinkat (path)
    - symlink, symlinkat (path, path)
    - readlink. readlinkat (path)
    - chmod (path)
    - chown, lchown (path)
    - setxattr, lsetxattr, fsetxattr, setxattrat
    - getxattr, lgetxattr, fgetxattr, getxattrat
    - listxattr, llistxattr, flistxattr, listxattrat
    - removexattr, lremovexattr, fremovexatt, removexattrat
- For mount
    - statmount (mnt_id)
    - chroot (path)
    - mount (dev, path)
    - umount (path)
- For superblock
    - statfs (path)
    - mknod, mknodat (path) -> fd
- For filesystem:
    - ustat (dev)
    - sysfs (fs name)
    - syncfs (fd)

```mermaid
sequenceDiagram
    title Open syscall
    userspace->>+sys_open: open(path)
        sys_open->>+dentries_cache: getDentry(path)
            dentries_cache-)-sys_open: null
        sys_open->>+Superblock: getDEntry(path)
        deactivate sys_open
            Superblock->>+INode: findINode
            INode-)-Superblock: INode
            Superblock->>+DEntry: createDEntry(path)
            deactivate Superblock
                DEntry->>dentries_cache: addDEntry(path, DEntry)
            DEntry-)-Superblock: DEntry
            activate Superblock
        Superblock-)-sys_open: DEntry
        activate sys_open
    sys_open-)-userspace: DEntry.inode.fd
```

# Referencing

Dentry: children reference parent
In-memory fs's: dentries start with refcount 2
Dentries reference inodes
File reference dentry
Path walk: reference curr and AFTER unreference prev
