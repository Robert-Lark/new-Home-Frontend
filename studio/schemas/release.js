//import { RiRecordCircleLine as icon } from 'react-icons/ri';
import PriceInput from '../components/PriceInput';

export default {
  name: 'release',
  title: 'Release',
  type: 'document',
  //icon,
  fields: [
    {
      name: 'name',
      title: 'Release Title',
      type: 'string',
      description: 'Title of the release',
    },
    {
      name: 'slug',
      title: 'Slug',
      type: 'slug',
      options: {
        source: 'name',
        maxLength: 100,
      },
    },
    {
      name: 'image',
      title: 'Image',
      type: 'image',
      options: {
        hotspot: true,
      },
    },
    {
      name: 'price',
      title: 'Price',
      type: 'number',
      description: 'Price of the release in cents',
      validation: Rule => Rule.min(1000),
     inputComponent: PriceInput,
    },
    {
      name: 'artists',
      title: 'Artists',
      type: 'array',
      of: [{ type: 'reference', to: [{ type: 'artist' }] }],
    },
    {
      name: 'label',
      title: 'Label',
      type: 'array',
      of: [{ type: 'reference', to: [{ type: 'label' }] }],
    },
  ],
  preview: {
    select: {
      title: 'name',
      media: 'image',
      label: 'label',
      artist0: 'artists.0.name',
      artist1: 'artists.1.name',
      artist2: 'artists.2.name',
      artist3: 'artists.3.name',
    },
    prepare: ({ title, media, ...artists }) => {
      // 1. Filter undefined artists out
      const arts = Object.values(artists).filter(Boolean);
      // 2. return the preview object for the release
      return {
        title,
        media,
        subtitle: arts.join(', '),
      };
    },
  },
};