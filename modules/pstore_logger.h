#ifndef PSTORE_LOGGER_H
#define PSTORE_LOGGER_H

 #include <linux/file.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/notifier.h>
#include <linux/namei.h>
#include <linux/dcache.h>
#include <linux/fs.h>

#define PSTORE_DIR "/sys/fs/pstore"
#define PANIC_LOG_PATH "/var/log/panic.log"

struct read_pstore_ctx {
    struct dir_context dir_ctx; 
    struct file *dest_file;
    char *buffer;
};

static inline int write_file_to_log(struct file *src_file, struct file *dest_file, char *buffer)
{
    loff_t src_pos = 0, dest_pos = dest_file->f_pos;
    ssize_t read_size, written_size;
    mm_segment_t old_fs;

    old_fs = get_fs();
    set_fs(KERNEL_DS);

    while ((read_size = vfs_read(src_file, buffer, PAGE_SIZE, &src_pos)) > 0) {
        written_size = vfs_write(dest_file, buffer, read_size, &dest_pos);
        if (written_size != read_size) {
            pr_err("Failed to write all data to panic log. Written: %zd\n", written_size);
            set_fs(old_fs);
            return -EIO;
        }
        dest_pos += written_size;
    }

    set_fs(old_fs);

    if (read_size < 0) {
        pr_err("Failed to read from source file: %zd\n", read_size);
        return read_size;
    }

    return 0;
}

static inline int process_pstore_entry(struct dir_context *ctx, const char *name, int len,
                                       loff_t offset, u64 ino, unsigned int d_type)
{
    struct read_pstore_ctx *pctx = container_of(ctx, struct read_pstore_ctx, dir_ctx);
    struct file *src_file;
    char *file_path;
    int ret = 0;

    if (!(d_type & DT_REG))
        return 0; // Skip non-regular files

    file_path = kmalloc(PATH_MAX, GFP_KERNEL);
    if (!file_path) {
        pr_err("Failed to allocate memory for file path.\n");
        ret = -ENOMEM;
        goto out;
    }

    snprintf(file_path, PATH_MAX, "%s/%s", PSTORE_DIR, name);

    src_file = filp_open(file_path, O_RDONLY, 0);
    if (IS_ERR(src_file)) {
        pr_err("Failed to open pstore file %s: %ld\n", file_path, PTR_ERR(src_file));
        ret = PTR_ERR(src_file);
        goto free_file_path;
    }

    pr_info("Processing pstore file: %s\n", file_path);

    ret = write_file_to_log(src_file, pctx->dest_file, pctx->buffer);

    filp_close(src_file, NULL);

free_file_path:
    kfree(file_path);

out:
    return ret;
}

static inline int write_panic_log_to_file(void)
{
    struct file *dest_file, *pstore_dir;
    struct path dir_path;
    struct read_pstore_ctx ctx;
    int ret;

    dest_file = filp_open(PANIC_LOG_PATH, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (IS_ERR(dest_file)) {
        pr_err("Failed to open panic log file: %ld\n", PTR_ERR(dest_file));
        return PTR_ERR(dest_file);
    }

    ret = kern_path(PSTORE_DIR, LOOKUP_DIRECTORY, &dir_path);
    if (ret) {
        pr_err("Failed to locate pstore directory: %d\n", ret);
        goto close_dest_file;
    }

    pstore_dir = dentry_open(&dir_path, O_RDONLY, current_cred());
    if (IS_ERR(pstore_dir)) {
        pr_err("Failed to open pstore directory: %ld\n", PTR_ERR(pstore_dir));
        ret = PTR_ERR(pstore_dir);
        goto close_dest_file;
    }

    ctx.dest_file = dest_file;
    ctx.buffer = kmalloc(PAGE_SIZE, GFP_KERNEL);
    if (!ctx.buffer) {
        pr_err("Failed to allocate buffer.\n");
        ret = -ENOMEM;
        goto close_pstore_dir;
    }

    ctx.dir_ctx.actor = process_pstore_entry;
    ctx.dir_ctx.pos = 0;

    // Iterate over the pstore directory entries
    ret = iterate_dir(pstore_dir, &ctx.dir_ctx);
    if (ret < 0) {
        pr_err("Failed to iterate pstore directory: %d\n", ret);
    }

    kfree(ctx.buffer);

close_pstore_dir:
    fput(pstore_dir);

close_dest_file:
    filp_close(dest_file, NULL);

    return ret;
}

#endif // PSTORE_LOGGER_H
