// 
// OptimizedPNG
// OptimizedPNG.m
// 
// The MIT License
// 
// Copyright (c) 2009 sonson, sonson@Picture&Software
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
////
//  Original source code
//  Created by takiuchi on 08/12/07.
//  Copyright 2008 s21g LLC. All rights reserved.
//  MIT Lisence
//

//
//  optimizedPNG.m
//  Created by sonson on 09/01/25.
//  Copyright 2009 sonson. All rights reserved.
//

#import "OptimizedPNG.h"
#import <zlib.h>

#pragma mark NSMutableData for Making Optimized PNG Image

@interface NSMutableData (pngTool)
- (void)appendUInt:(NSUInteger)value;
@end

@implementation NSMutableData (pngTool)
- (void) appendUInt:(NSUInteger)value {
	value = htonl(value);
	[self appendBytes:&value length:sizeof(value)];
}
@end

unsigned int crc(unsigned char *name, unsigned char *buf, int len) {
	unsigned int crc = crc32(0, name, 4);
	return crc32(crc, buf, len);
}

#pragma mark PNG Chunk

unsigned char PNGHeader[8] = {137, 80, 78, 71, 13, 10, 26, 10};
unsigned char PNGChunkHdr[4] = {0x49, 0x48, 0x44, 0x52};
unsigned char PNGChunkData[4] = {0x49, 0x44, 0x41, 0x54};													// IDAT
unsigned char PNGChunkEnd[8] = {0x49, 0x45, 0x4e, 0x44, 0xAE, 0x42, 0x60, 0x82};							// IEND
unsigned char PNGChunkCgBI[12] = {0x43, 0x67, 0x42, 0x49, 0x30, 0x00, 0x20, 0x06, 0x17, 0x9E, 0x80, 0x65};	// CgBI

#pragma mark Make Optimized PNG

NSData* makeOptimizedPNGDataFromUIImage( UIImage *originalImage ) {
	NSMutableData *data = [NSMutableData new];
	[data appendBytes:PNGHeader length:8];
	
	// CgBI
	[data appendUInt:4];
	[data appendBytes:PNGChunkCgBI length:12];
	
	// IHDR
	unsigned char hdr[13];
	int width = originalImage.size.width, height = originalImage.size.height;
	*(unsigned int*)(hdr + 0) = htonl(width);
	*(unsigned int*)(hdr + 4) = htonl(height);
	*(unsigned char*)(hdr + 8) = 8;
	*(unsigned char*)(hdr + 9) = 6;
	*(unsigned char*)(hdr + 10) = 0;
	*(unsigned char*)(hdr + 11) = 0;
	*(unsigned char*)(hdr + 12) = 0;
	[data appendUInt:13];
	[data appendBytes:PNGChunkHdr length:4];
	[data appendBytes:hdr length:13];
	[data appendUInt:crc(PNGChunkHdr, hdr, 13)];
	
	// IDAT
	int size = width*height*4;
	unsigned char *buffer = malloc(size);
	CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8, width*4, CGImageGetColorSpace(originalImage.CGImage), kCGImageAlphaPremultipliedLast);
	CGRect rect = CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height);
	CGContextDrawImage(context, rect, originalImage.CGImage);
	CGContextRelease(context);
	
	int size_line = 1 + width*4;
	int size_in = height*size_line;
	unsigned char *buffer_in = malloc(size_in);
	for(int y = 0; y < height; ++y){
		unsigned char *src = &buffer[y*width*4];
		unsigned char *dst = &buffer_in[y*size_line];
		*dst++ = 1;
		unsigned char r = 0, g = 0, b = 0, a = 0;
		for(int x = 0; x < width; ++x){
			dst[0] = src[2] - b;
			dst[1] = src[1] - g;
			dst[2] = src[0] - r;
			dst[3] = src[3] - a;
			r = src[0], g = src[1], b = src[2], a = src[3];
			src += 4;
			dst += 4;
		}
	}
	free(buffer);
	
	unsigned char *buffer_out = malloc(size_in);
	z_stream stream;
	stream.zalloc = Z_NULL;
	stream.zfree = Z_NULL;
	stream.opaque = Z_NULL;
	stream.avail_in = size_in;
	stream.next_in = buffer_in;
	stream.next_out = buffer_out;
	stream.avail_out = size_in;
	deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -8, MAX_MEM_LEVEL, Z_DEFAULT_STRATEGY);
	deflate(&stream, Z_FINISH);
	free(buffer_in);
	
	[data appendUInt:stream.total_out];
	[data appendBytes:PNGChunkData length:4];
	[data appendBytes:buffer_out length:stream.total_out];
	[data appendUInt:crc(PNGChunkData, buffer_out, stream.total_out)];
	free(buffer_out);
	deflateEnd(&stream);
	
	// IEND
	[data appendUInt:0];
	[data appendBytes:PNGChunkEnd length:8];
	
	return data;	
}

#pragma mark UIImage (optimizedPNG) implementation

@implementation UIImage (optimizedPNG)
- (NSData*)optimizedData {
	return makeOptimizedPNGDataFromUIImage( self );
}
@end

#pragma mark NSData (optimizedPNG) implementation

@implementation NSData (optimizedPNG)
- (NSData*)optimizedData {
	// decode image
	UIImage* originalImage = [UIImage imageWithData:self];
	if( originalImage == nil ) {
		NSLog( @"Can't decode NSData into image." );
		return nil;
	}
	return makeOptimizedPNGDataFromUIImage( originalImage );
}
@end