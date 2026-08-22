import { Injectable, NotFoundException } from '@nestjs/common';
import { Journal, JournalStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { CreateJournalDto } from './dto/create-journal.dto';
import { UpdateJournalDto } from './dto/update-journal.dto';
import { ListJournalsQueryDto } from './dto/list-journals-query.dto';
import { JournalDto } from './dto/journal.dto';

@Injectable()
export class JournalService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  async adminCreate(dto: CreateJournalDto): Promise<JournalDto> {
    const slug = await this.resolveSlug(dto.slug ?? dto.title);
    const journal = await this.prisma.journal.create({
      data: {
        slug,
        title: dto.title,
        label: dto.label,
        excerpt: dto.excerpt,
        content: dto.content,
      },
    });
    return this.toDto(journal);
  }

  async adminList(query: ListJournalsQueryDto): Promise<JournalDto[]> {
    const journals = await this.prisma.journal.findMany({
      where: { status: query.status, label: query.label },
      orderBy: { updatedAt: 'desc' },
    });
    return Promise.all(journals.map((journal) => this.toDto(journal)));
  }

  async adminGet(id: number): Promise<JournalDto> {
    return this.toDto(await this.findOrThrow(id));
  }

  async adminUpdate(id: number, dto: UpdateJournalDto): Promise<JournalDto> {
    await this.findOrThrow(id);
    const data: Prisma.JournalUpdateInput = {
      title: dto.title,
      label: dto.label,
      excerpt: dto.excerpt,
      content: dto.content,
    };
    if (dto.slug !== undefined) {
      data.slug = await this.resolveSlug(dto.slug, id);
    }
    const journal = await this.prisma.journal.update({ where: { id }, data });
    return this.toDto(journal);
  }

  async adminSetStatus(id: number, status: JournalStatus): Promise<JournalDto> {
    await this.findOrThrow(id);
    const journal = await this.prisma.journal.update({
      where: { id },
      data: {
        status,
        publishedAt: status === JournalStatus.PUBLISHED ? new Date() : null,
      },
    });
    return this.toDto(journal);
  }

  async adminDelete(id: number): Promise<void> {
    const journal = await this.findOrThrow(id);
    await this.prisma.journal.delete({ where: { id } });
    if (journal.coverImageKey) {
      await this.storage.deleteObject(journal.coverImageKey);
    }
  }

  private async findOrThrow(id: number): Promise<Journal> {
    const journal = await this.prisma.journal.findUnique({ where: { id } });
    if (!journal) {
      throw new NotFoundException('Journal not found');
    }
    return journal;
  }

  // Builds a unique, URL-safe slug from arbitrary input (handles Vietnamese
  // diacritics). On update, the row's own id is excluded so it can keep its
  // current slug. Appends -2, -3, ... on collision.
  private async resolveSlug(
    input: string,
    excludeId?: number,
  ): Promise<string> {
    const base =
      input
        .toLowerCase()
        .normalize('NFD')
        .replace(/[̀-ͯ]/g, '')
        .replace(/[đĐ]/g, 'd')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 200) || 'journal';
    let slug = base;
    let suffix = 2;
    for (;;) {
      const clash = await this.prisma.journal.findFirst({
        where: {
          slug,
          id: excludeId !== undefined ? { not: excludeId } : undefined,
        },
        select: { id: true },
      });
      if (!clash) {
        return slug;
      }
      slug = `${base}-${suffix++}`;
    }
  }

  private async toDto(journal: Journal): Promise<JournalDto> {
    let coverImageUrl: string | null = null;
    if (journal.coverImageKey) {
      const { url } = await this.storage.getSignedDownloadUrl(
        journal.coverImageKey,
      );
      coverImageUrl = url;
    }
    return {
      id: journal.id,
      slug: journal.slug,
      title: journal.title,
      label: journal.label,
      excerpt: journal.excerpt,
      content: journal.content,
      coverImageUrl,
      status: journal.status,
      publishedAt: journal.publishedAt
        ? journal.publishedAt.toISOString()
        : null,
      createdAt: journal.createdAt.toISOString(),
      updatedAt: journal.updatedAt.toISOString(),
    };
  }
}
