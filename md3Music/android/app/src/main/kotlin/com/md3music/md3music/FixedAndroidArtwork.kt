package com.md3music.md3music

import org.jaudiotagger.tag.images.AndroidArtwork
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

/**
 * 修复版 AndroidArtwork：JAudioTagger 社区分叉的 AndroidArtwork
 * 在 setImageFromData() 中调用了 javax.imageio.ImageIO（Android 不存在），
 * 导致 FlacTag.createField() 抛出 UnsupportedOperationException。
 *
 * 本类用 FileInputStream 手动读取图片字节，绕过 ImageIO 依赖。
 *
 * 用法：用 FixedAndroidArtwork(file) 替代 ArtworkFactory.createArtworkFromFile(file)
 */
class FixedAndroidArtwork(private val imageFile: File) : AndroidArtwork() {

    init {
        // 设置文件路径（父类字段）
        filePath = imageFile.absolutePath
        // 设置 MIME 类型
        mimeType = when {
            imageFile.name.endsWith(".png", true) -> "image/png"
            imageFile.name.endsWith(".webp", true) -> "image/webp"
            else -> "image/jpeg"
        }
    }

    override fun setImageFromData(imageData: ByteArray) {
        // 不依赖 ImageIO，直接存储原始字节
        binaryData = imageData
    }

    override fun getImageFromData(): ByteArray {
        // 从文件读取图片字节，编码为 FLAC METADATA_BLOCK_PICTURE 格式
        val imageBytes = readFileBytes(imageFile)
        return encodeAsFlacPictureBlock(imageBytes)
    }

    override fun isBinaryDataExists(): Boolean {
        return imageFile.exists() && imageFile.length() > 0
    }

    /** 读取文件全部字节 */
    private fun readFileBytes(file: File): ByteArray {
        val buffer = ByteArray(8192)
        val output = ByteArrayOutputStream()
        FileInputStream(file).use { input ->
            var bytesRead: Int
            while (input.read(buffer).also { bytesRead = it } != -1) {
                output.write(buffer, 0, bytesRead)
            }
        }
        return output.toByteArray()
    }

    /**
     * 将图片字节编码为 FLAC METADATA_BLOCK_PICTURE 二进制格式。
     * 格式参考：https://xiph.org/flac/format.html#metadata_block_picture
     *
     * 结构：
     *   [4 bytes] picture type (3 = Cover Front)
     *   [4 bytes] MIME type length
     *   [N bytes] MIME type (UTF-8)
     *   [4 bytes] description length
     *   [N bytes] description (UTF-8)
     *   [4 bytes] width
     *   [4 bytes] height
     *   [4 bytes] color depth
     *   [4 bytes] number of indexed colors (0 for non-indexed)
     *   [4 bytes] data length
     *   [N bytes] data
     */
    private fun encodeAsFlacPictureBlock(imageBytes: ByteArray): ByteArray {
        val mimeBytes = (mimeType ?: "image/jpeg").toByteArray(StandardCharsets.UTF_8)
        val descBytes = ByteArray(0) // 无描述

        val buffer = ByteBuffer.allocate(4 + 4 + mimeBytes.size + 4 + descBytes.size + 4 + 4 + 4 + 4 + 4 + imageBytes.size)
        buffer.putInt(3)                          // picture type: 3 = Cover (front)
        buffer.putInt(mimeBytes.size)             // MIME type length
        buffer.put(mimeBytes)                     // MIME type
        buffer.putInt(descBytes.size)             // description length
        buffer.put(descBytes)                     // description
        buffer.putInt(0)                          // width (未知)
        buffer.putInt(0)                          // height (未知)
        buffer.putInt(24)                         // color depth (默认 24-bit)
        buffer.putInt(0)                          // indexed colors (0 = 非索引)
        buffer.putInt(imageBytes.size)            // data length
        buffer.put(imageBytes)                    // data

        return buffer.array()
    }
}
