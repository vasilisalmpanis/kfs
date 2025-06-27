# Full Storage Stack Implementation Plan

## Architecture Overview
```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
├─────────────────────────────────────────────────────────────┤
│                  System Call Interface                      │
│                 (open, read, write, close)                  │
├─────────────────────────────────────────────────────────────┤
│                Virtual File System (VFS)                    │
│            (unified interface for all filesystems)          │
├─────────────────────────────────────────────────────────────┤
│                   File System Layer                         │
│                      (EXT2, FAT32)                          │
├─────────────────────────────────────────────────────────────┤
│                  Block Device Layer                         │
│               (generic block operations)                    │
├─────────────────────────────────────────────────────────────┤
│                   Device Drivers                            │
│                   (PATA, AHCI)                              │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: Block Device Infrastructure (Week 1-2)

### 1.1 Generic Block Device Interface
Create an abstraction layer that sits above your PATA driver:

```c
// Core block device structure
typedef struct block_device {
    char name[16];              // "hda", "hdb", etc.
    uint32_t sector_size;       // Usually 512 bytes
    uint64_t num_sectors;       // Total sectors on device
    uint32_t max_transfer;      // Max sectors per transfer
    
    // Operations
    int (*read)(struct block_device *dev, uint64_t sector, 
                uint32_t count, void *buffer);
    int (*write)(struct block_device *dev, uint64_t sector, 
                 uint32_t count, void *buffer);
    int (*flush)(struct block_device *dev);
    
    // Driver-specific data
    void *private_data;
    
    // List management
    struct block_device *next;
} block_device_t;
```

### 1.2 Block Device Manager
```c
// Register/unregister block devices
int register_block_device(block_device_t *dev);
int unregister_block_device(const char *name);
block_device_t *find_block_device(const char *name);

// List all devices
void list_block_devices(void);
```

### 1.3 Buffer Cache (Critical for Performance)
```c
typedef struct buffer_head {
    uint64_t sector;            // Sector number
    block_device_t *device;     // Which device
    void *data;                 // 512-byte buffer
    uint32_t flags;             // DIRTY, VALID, etc.
    uint32_t ref_count;         // Reference counting
    struct buffer_head *next;   // Hash chain
    struct buffer_head *lru_next, *lru_prev; // LRU list
} buffer_head_t;

// Buffer cache operations
buffer_head_t *get_buffer(block_device_t *dev, uint64_t sector);
void put_buffer(buffer_head_t *bh);
int sync_buffer(buffer_head_t *bh);
void sync_all_buffers(void);
```

## Phase 2: Partition Support (Week 2-3)

### 2.1 MBR Partition Table Parser
```c
typedef struct {
    uint8_t status;         // 0x80 = bootable
    uint8_t first_chs[3];   // Start CHS (obsolete)
    uint8_t type;           // Partition type (0x83 = Linux)
    uint8_t last_chs[3];    // End CHS (obsolete)
    uint32_t first_lba;     // Start sector (LBA)
    uint32_t num_sectors;   // Size in sectors
} __attribute__((packed)) mbr_partition_t;

typedef struct {
    uint8_t bootstrap[446];
    mbr_partition_t partitions[4];
    uint16_t signature;     // 0xAA55
} __attribute__((packed)) mbr_t;

// Parse MBR and create partition devices
int parse_mbr(block_device_t *disk);
```

### 2.2 Partition Block Devices
Create virtual block devices for each partition:
- `hda1`, `hda2`, etc. that redirect to parent device with offset

## Phase 3: Virtual File System (VFS) (Week 3-5)

### 3.1 Core VFS Structures
```c
// Superblock - represents a mounted filesystem
typedef struct superblock {
    block_device_t *device;     // Underlying device
    uint32_t block_size;        // Filesystem block size
    uint64_t total_blocks;      // Total blocks in filesystem
    uint64_t free_blocks;       // Free blocks
    
    // Filesystem-specific operations
    struct super_operations *ops;
    void *private_data;         // FS-specific data
    
    // Root inode
    struct inode *root_inode;
    
    // Mount information
    char mount_point[256];
    struct superblock *next;
} superblock_t;

// Inode - represents a file or directory
typedef struct inode {
    uint32_t ino;               // Inode number
    uint16_t mode;              // File type and permissions
    uint16_t uid, gid;          // Owner and group
    uint32_t size;              // File size in bytes
    uint32_t atime, mtime, ctime; // Access, modify, create times
    uint32_t blocks;            // Number of blocks allocated
    
    superblock_t *sb;           // Superblock this inode belongs to
    struct inode_operations *ops; // Inode operations
    void *private_data;         // FS-specific inode data
    
    // Reference counting
    uint32_t ref_count;
} inode_t;

// Directory entry
typedef struct dentry {
    char name[256];             // Filename
    inode_t *inode;             // Inode this entry points to
    struct dentry *parent;      // Parent directory
    struct dentry *next_sibling; // Next entry in directory
    struct dentry *child;       // First child (if directory)
} dentry_t;

// Open file descriptor
typedef struct file {
    inode_t *inode;             // File's inode
    uint64_t pos;               // Current file position
    uint32_t flags;             // O_RDONLY, O_WRONLY, etc.
    struct file_operations *ops; // File operations
    void *private_data;         // FS-specific file data
} file_t;
```

### 3.2 VFS Operations
```c
// Superblock operations
struct super_operations {
    int (*read_inode)(inode_t *inode);
    int (*write_inode)(inode_t *inode);
    int (*delete_inode)(inode_t *inode);
    int (*sync_fs)(superblock_t *sb);
};

// Inode operations
struct inode_operations {
    int (*lookup)(inode_t *dir, const char *name, inode_t **result);
    int (*create)(inode_t *dir, const char *name, uint16_t mode);
    int (*mkdir)(inode_t *dir, const char *name, uint16_t mode);
    int (*rmdir)(inode_t *dir, const char *name);
    int (*unlink)(inode_t *dir, const char *name);
};

// File operations
struct file_operations {
    ssize_t (*read)(file_t *file, void *buffer, size_t count);
    ssize_t (*write)(file_t *file, const void *buffer, size_t count);
    int (*seek)(file_t *file, off_t offset, int whence);
    int (*readdir)(file_t *file, void *buffer, filldir_t filldir);
};
```

### 3.3 VFS Core Functions
```c
// Mount/unmount
int mount_filesystem(const char *device, const char *mountpoint, 
                    const char *fstype);
int unmount_filesystem(const char *mountpoint);

// Path resolution
int path_lookup(const char *path, inode_t **result);

// File operations
int vfs_open(const char *path, int flags, file_t **result);
ssize_t vfs_read(file_t *file, void *buffer, size_t count);
ssize_t vfs_write(file_t *file, const void *buffer, size_t count);
int vfs_close(file_t *file);
```

## Phase 4: EXT2 Filesystem (Week 5-8)

### 4.1 EXT2 Data Structures
```c
// EXT2 Superblock (stored at offset 1024)
typedef struct {
    uint32_t inodes_count;      // Total inodes
    uint32_t blocks_count;      // Total blocks
    uint32_t free_blocks_count; // Free blocks
    uint32_t free_inodes_count; // Free inodes
    uint32_t first_data_block;  // First data block
    uint32_t log_block_size;    // Block size = 1024 << log_block_size
    uint32_t log_frag_size;     // Fragment size
    uint32_t blocks_per_group;  // Blocks per group
    uint32_t frags_per_group;   // Fragments per group
    uint32_t inodes_per_group;  // Inodes per group
    // ... more fields
    uint16_t magic;             // 0xEF53
} __attribute__((packed)) ext2_superblock_t;

// Block Group Descriptor
typedef struct {
    uint32_t block_bitmap;      // Block bitmap block
    uint32_t inode_bitmap;      // Inode bitmap block
    uint32_t inode_table;       // Inode table start block
    uint16_t free_blocks_count; // Free blocks in group
    uint16_t free_inodes_count; // Free inodes in group
    uint16_t used_dirs_count;   // Directories in group
    uint16_t pad;
    uint8_t reserved[12];
} __attribute__((packed)) ext2_group_desc_t;

// EXT2 Inode
typedef struct {
    uint16_t mode;              // File mode
    uint16_t uid;               // Owner UID
    uint32_t size;              // File size
    uint32_t atime;             // Access time
    uint32_t ctime;             // Creation time
    uint32_t mtime;             // Modification time
    uint32_t dtime;             // Deletion time
    uint16_t gid;               // Group ID
    uint16_t links_count;       // Hard links count
    uint32_t blocks;            // Number of blocks
    uint32_t flags;             // File flags
    uint32_t block[15];         // Block pointers (12 direct + 3 indirect)
    uint32_t generation;        // File version
    uint32_t file_acl;          // File ACL
    uint32_t dir_acl;           // Directory ACL
    uint32_t faddr;             // Fragment address
    uint8_t osd2[12];           // OS dependent
} __attribute__((packed)) ext2_inode_t;

// Directory Entry
typedef struct {
    uint32_t inode;             // Inode number
    uint16_t rec_len;           // Record length
    uint8_t name_len;           // Name length
    uint8_t file_type;          // File type
    char name[];                // Filename (variable length)
} __attribute__((packed)) ext2_dir_entry_t;
```

### 4.2 EXT2 Implementation Steps

1. **Superblock Reading**: Parse EXT2 superblock, validate magic number
2. **Block Group Management**: Read block group descriptors
3. **Bitmap Management**: Handle block and inode bitmaps
4. **Inode Operations**: Read/write inodes from inode table
5. **Block Allocation**: Allocate/free blocks using bitmaps
6. **Directory Operations**: Parse directory entries, implement lookup
7. **File I/O**: Handle direct, indirect, and double-indirect blocks
8. **Integration**: Connect to VFS layer

## Phase 5: System Call Interface (Week 8-9)

### 5.1 POSIX-like System Calls
```c
// File descriptor table (per process)
#define MAX_FDS 256
typedef struct {
    file_t *files[MAX_FDS];
    uint32_t fd_flags[MAX_FDS];
} fd_table_t;

// System calls
int sys_open(const char *pathname, int flags, mode_t mode);
ssize_t sys_read(int fd, void *buf, size_t count);
ssize_t sys_write(int fd, const void *buf, size_t count);
off_t sys_lseek(int fd, off_t offset, int whence);
int sys_close(int fd);
int sys_unlink(const char *pathname);
int sys_mkdir(const char *pathname, mode_t mode);
int sys_rmdir(const char *pathname);
```

## Testing Strategy

### Create Test EXT2 Image
```bash
# Create 10MB image
dd if=/dev/zero of=test.img bs=1M count=10

# Format as EXT2
mkfs.ext2 test.img

# Mount and add test files
sudo mount -o loop test.img /mnt
sudo cp some_files /mnt/
sudo umount /mnt

# Use in QEMU
qemu-system-x86_64 -hda test.img ...
```

### Test Cases
1. **Block Device**: Read/write raw sectors
2. **Partition**: Parse MBR, access partitions
3. **EXT2 Mount**: Mount filesystem, read superblock
4. **Directory Listing**: List root directory contents
5. **File Reading**: Read existing files
6. **File Creation**: Create new files
7. **Directory Operations**: Create/remove directories

## Implementation Tips

1. **Start Simple**: Begin with read-only EXT2 support
2. **Use Existing Tools**: Create test images with standard Linux tools
3. **Debug Output**: Add extensive logging for each layer
4. **Incremental Testing**: Test each layer independently
5. **Error Handling**: Handle corruption gracefully
6. **Performance**: Implement buffer cache early

## Common Pitfalls

1. **Endianness**: EXT2 uses little-endian, ensure proper conversion
2. **Block Sizes**: EXT2 block size != sector size (usually 1024 vs 512)
3. **Alignment**: Ensure structures are properly packed
4. **Reference Counting**: Prevent memory leaks in VFS layer
5. **Locking**: Add proper synchronization for multi-threading

This is a substantial project that will teach you about every aspect of storage systems. Start with Phase 1 and work your way through systematically!
