import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InviteStatus, TripNote } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTripNoteDto } from './dto/create-trip-note.dto';
import { TripNoteDto } from './dto/trip-note.dto';
import { TripNoteListDto } from './dto/trip-note-list.dto';
import { UpdateTripNoteDto } from './dto/update-trip-note.dto';

@Injectable()
export class TripNotesService {
  constructor(private readonly prisma: PrismaService) {}

  async listNotes(tripId: number, userId: number): Promise<TripNoteListDto> {
    await this.assertMember(tripId, userId);

    const notes = await this.prisma.tripNote.findMany({
      where: { tripId },
      orderBy: { id: 'desc' },
    });

    return { data: notes.map((note) => this.formatNote(note)) };
  }

  async createNote(
    tripId: number,
    userId: number,
    dto: CreateTripNoteDto,
  ): Promise<TripNoteDto> {
    await this.assertMember(tripId, userId);

    const note = await this.prisma.tripNote.create({
      data: {
        tripId,
        createdById: userId,
        title: dto.title,
        body: dto.body ?? null,
        isDone: dto.isDone ?? false,
      },
    });

    return this.formatNote(note);
  }

  async updateNote(
    tripId: number,
    noteId: number,
    userId: number,
    dto: UpdateTripNoteDto,
  ): Promise<TripNoteDto> {
    await this.assertMember(tripId, userId);
    await this.assertNoteBelongsToTrip(noteId, tripId);

    const note = await this.prisma.tripNote.update({
      where: { id: noteId },
      data: {
        ...(dto.title !== undefined ? { title: dto.title } : {}),
        ...(dto.body !== undefined ? { body: dto.body } : {}),
        ...(dto.isDone !== undefined ? { isDone: dto.isDone } : {}),
        updatedAt: new Date(),
      },
    });

    return this.formatNote(note);
  }

  async deleteNote(
    tripId: number,
    noteId: number,
    userId: number,
  ): Promise<void> {
    await this.assertMember(tripId, userId);
    await this.assertNoteBelongsToTrip(noteId, tripId);

    await this.prisma.tripNote.delete({ where: { id: noteId } });
  }

  // ── Private helpers ──────────────────────────────────────────────

  private async assertMember(tripId: number, userId: number): Promise<void> {
    const member = await this.prisma.tripMember.findUnique({
      where: { tripId_userId: { tripId, userId } },
    });

    if (!member || member.inviteStatus !== InviteStatus.ACCEPTED) {
      throw new ForbiddenException('You are not a member of this trip');
    }
  }

  private async assertNoteBelongsToTrip(
    noteId: number,
    tripId: number,
  ): Promise<void> {
    const note = await this.prisma.tripNote.findUnique({
      where: { id: noteId },
      select: { tripId: true },
    });

    if (!note || note.tripId !== tripId) {
      throw new NotFoundException('Note not found');
    }
  }

  private formatNote(note: TripNote): TripNoteDto {
    return {
      id: note.id,
      tripId: note.tripId,
      createdById: note.createdById,
      title: note.title,
      body: note.body,
      isDone: note.isDone,
      createdAt: note.createdAt.toISOString(),
      updatedAt: note.updatedAt.toISOString(),
    };
  }
}
