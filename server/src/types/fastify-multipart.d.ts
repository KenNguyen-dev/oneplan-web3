import 'fastify';

interface MultipartFile {
  type: 'file';
  toBuffer: () => Promise<Buffer>;
  fieldname: string;
  filename: string;
  encoding: string;
  mimetype: string;
}

declare module 'fastify' {
  interface FastifyRequest {
    file: () => Promise<MultipartFile | undefined>;
    isMultipart: () => boolean;
  }
}
