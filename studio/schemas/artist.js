
export default {
  name: 'artist',
  title: 'Artists',
  type: 'document',
  fields: [
    {
      name: 'name',
      title: 'Name',
      type: 'string',
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
      name: 'description',
      title: 'Description',
      type: 'text',
      description: 'Tell us a bit about this artist',
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
      name: 'releases',
      title: 'Releases',
      type: 'array',
      of: [{ type: 'reference', to: [{ type: 'release' }] }],
    },
    {
        name: 'label',
        title: 'Label(s)',
        type: 'array',
        of: [{ type: 'reference', to: [{ type: 'label' }] }],
      },
  ],
  preview: {
    select: {
      name: 'name',
    },
    prepare: ({ name}) => ({
      title: `${name}`,
    }),
  },
};